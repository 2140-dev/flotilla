{
  config,
  lib,
  pkgs,
  ...
}:

# Workaround for an upstream frigate-1.5.2 cascading-freeze bug:
# Index.getHistoryAsync holds the DuckDB ReentrantReadWriteLock(fair=true)
# read lock across a multi-second GPU-backed scan. Timer-0 (block indexer)
# then queues on the write lock; because the lock is fair, all subsequent
# readers queue behind the writer and the server stops servicing queries.
# A frigate restart clears it. This file should be removed once upstream
# ships a fix.
#
# Two timer-driven oneshots:
#   - probe: every 60s, runs liveness (server.version + blockchain.headers.subscribe)
#            + CLOSE-WAIT canary, writes status.json. The second RPC call
#            touches frigate's IndexQuerier, so a DB-lock cascade that leaves
#            request dispatch alive but the index path stuck shows up as a
#            timeout instead of staying green.
#   - act:   every 60s offset 30s, reads status.json, SIGKILLs frigate
#            if two consecutive bad probes (subject to cooldown + rate limit)
#
# Watchdog SIGKILLs directly because by the time the act phase fires, we
# know frigate is wedged — there's nothing to gain from a SIGTERM-then-wait.
# Restart=on-failure on frigate.service brings it back up after ~10s.

let
  stateDir = "/var/lib/frigate-watchdog";

  # Tunables. Kept here rather than as module options because this whole
  # file is a temporary workaround.
  pingTimeoutSecs = 10;
  closeWaitThreshold = 25;
  consecutiveBadThreshold = 2;
  cooldownSecs = 30 * 60;
  maxRestartsInWindow = 3;
  windowSecs = 6 * 60 * 60;
  maxStatusAgeSecs = 180;
  minActiveBeforeRestartSecs = 3 * 60;
  fulcrumPeer = "10.42.0.3:60001";

  ssBin = "${pkgs.iproute2}/bin/ss";
  journalctlBin = "${pkgs.systemd}/bin/journalctl";
  systemctlBin = "${pkgs.systemd}/bin/systemctl";

  # E501 (line length) is suppressed because nix-interpolated store paths
  # like /nix/store/HASH-systemd-260.1/bin/systemctl exceed 79 chars on a
  # single line and breaking them only hurts readability.
  pythonWriterArgs = {
    flakeIgnore = [ "E501" ];
  };

  probe = pkgs.writers.writePython3Bin "frigate-watchdog-probe" pythonWriterArgs ''
    """Frigate health probe: liveness + CLOSE-WAIT canary + indexer freshness.

    Writes a single-line JSON status to ${stateDir}/status.json on every run.
    Exits 0 if healthy, 1 if any check tripped (so the journal shows
    a natural success/failure pattern for grepping).
    """
    import json
    import socket
    import subprocess
    import sys
    import time
    from pathlib import Path

    STATE_DIR = Path("${stateDir}")
    STATUS_FILE = STATE_DIR / "status.json"

    PING_TIMEOUT_SECS = ${toString pingTimeoutSecs}
    CLOSE_WAIT_THRESHOLD = ${toString closeWaitThreshold}
    FULCRUM_PEER = "${fulcrumPeer}"

    SS_BIN = "${ssBin}"
    JOURNALCTL_BIN = "${journalctlBin}"


    def probe_ping():
        """Connect to frigate's plaintext Electrum port and round-trip two
        requests on a single connection:

          1. server.version — frigate enforces version negotiation as the
             first message; this exercises request dispatch but is a no-op
             as far as DB / backend are concerned.
          2. blockchain.headers.subscribe — reads the current best block
             from frigate's local index, touching the IndexQuerier path
             that holds DuckDB's read lock. A pure-DB-lock cascade where
             dispatch stays alive but index reads queue behind a writer
             surfaces here as a recv timeout. We accept any timely response
             (including an RPC error body) as proof the index path is alive;
             the wedge symptom is a stuck recv, not an error payload.
        """
        version_req = (
            b'{"jsonrpc":"2.0","method":"server.version",'
            b'"id":1,"params":["frigate-watchdog","1.4"]}\n'
        )
        headers_req = (
            b'{"jsonrpc":"2.0","method":"blockchain.headers.subscribe",'
            b'"id":2,"params":[]}\n'
        )

        def recv_line(s, buf):
            while b"\n" not in buf:
                chunk = s.recv(4096)
                if not chunk:
                    return None, buf
                buf += chunk
            line, _, rest = buf.partition(b"\n")
            return line, rest

        start = time.monotonic()
        try:
            with socket.create_connection(
                ("127.0.0.1", 50001), timeout=PING_TIMEOUT_SECS
            ) as s:
                s.settimeout(PING_TIMEOUT_SECS)

                s.sendall(version_req)
                line, buf = recv_line(s, b"")
                if line is None:
                    return False, (time.monotonic() - start) * 1000, "version:eof"
                resp = json.loads(line)
                if resp.get("error") is not None:
                    elapsed_ms = (time.monotonic() - start) * 1000
                    return False, elapsed_ms, f"version_rpc_error:{resp['error']}"
                result = resp.get("result")
                if not (isinstance(result, list) and len(result) == 2):
                    elapsed_ms = (time.monotonic() - start) * 1000
                    return False, elapsed_ms, f"version_bad_shape:{result!r}"

                s.sendall(headers_req)
                line, _ = recv_line(s, buf)
                elapsed_ms = (time.monotonic() - start) * 1000
                if line is None:
                    return False, elapsed_ms, "headers:eof"
                # Any well-formed JSON response — including an RPC error —
                # proves the index path is responsive. Only a stuck recv
                # (caught as socket.timeout above) or malformed JSON fails.
                json.loads(line)
                return True, elapsed_ms, None
        except (socket.timeout, TimeoutError):
            return False, PING_TIMEOUT_SECS * 1000, "timeout"
        except (OSError, ValueError) as e:
            return False, (time.monotonic() - start) * 1000, f"{type(e).__name__}:{e}"


    def probe_close_wait():
        try:
            out = subprocess.run(
                [SS_BIN, "-tnH", "state", "close-wait"],
                capture_output=True, text=True, timeout=5,
            ).stdout
        except (subprocess.TimeoutExpired, OSError):
            return -1
        return sum(1 for line in out.splitlines() if FULCRUM_PEER in line)


    def probe_indexer_silence_min():
        # Informational only — not yet a restart trigger. Caveat: a fresh
        # frigate startup floods the journal with "Indexed N blocks" lines
        # from catch-up, so this value drops to ~0 after every restart even
        # if the indexer subsequently wedges seconds later. Promote to a
        # trigger only after steady-state log behavior is characterized.
        try:
            out = subprocess.run(
                [JOURNALCTL_BIN, "-u", "frigate.service",
                 "--since", "2 hours ago", "-o", "short-unix",
                 "--no-pager", "--grep=Indexed [0-9]+ "],
                capture_output=True, text=True, timeout=10,
            ).stdout
        except (subprocess.TimeoutExpired, OSError):
            return -1
        lines = [ln for ln in out.splitlines() if ln and ln[0].isdigit()]
        if not lines:
            return 120
        try:
            last_ts = float(lines[-1].split(None, 1)[0])
        except (IndexError, ValueError):
            return -1
        return max(0, int((time.time() - last_ts) / 60))


    def main():
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        ping_ok, ping_ms, ping_err = probe_ping()
        close_wait = probe_close_wait()
        indexer_min = probe_indexer_silence_min()

        if not ping_ok:
            verdict = "ping_failed"
        elif close_wait > CLOSE_WAIT_THRESHOLD:
            verdict = "close_wait_high"
        else:
            verdict = "healthy"

        status = {
            "ts": int(time.time()),
            "ping_ok": ping_ok,
            "ping_ms": round(ping_ms, 1),
            "ping_err": ping_err,
            "close_wait": close_wait,
            "indexer_silent_min": indexer_min,
            "verdict": verdict,
        }
        tmp = STATUS_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(status) + "\n")
        tmp.replace(STATUS_FILE)
        print(json.dumps(status))
        sys.exit(0 if verdict == "healthy" else 1)


    if __name__ == "__main__":
        main()
  '';

  act = pkgs.writers.writePython3Bin "frigate-watchdog-act" pythonWriterArgs ''
    """Frigate watchdog act phase: read status, SIGKILL frigate if wedge confirmed.

    Wedge confirmation requires ${toString consecutiveBadThreshold} consecutive
    bad probes. Subject to a ${toString (cooldownSecs / 60)} min cooldown and
    a ${toString maxRestartsInWindow}-restarts-per-${toString (windowSecs / 3600)}h
    ceiling.
    """
    import json
    import subprocess
    import sys
    import time
    from pathlib import Path

    STATE_DIR = Path("${stateDir}")
    STATUS_FILE = STATE_DIR / "status.json"
    STATE_FILE = STATE_DIR / "state.json"
    RESTART_LOG = STATE_DIR / "restarts.log"

    CONSECUTIVE_BAD_THRESHOLD = ${toString consecutiveBadThreshold}
    COOLDOWN_SECS = ${toString cooldownSecs}
    MAX_RESTARTS_IN_WINDOW = ${toString maxRestartsInWindow}
    WINDOW_SECS = ${toString windowSecs}
    MAX_STATUS_AGE_SECS = ${toString maxStatusAgeSecs}
    MIN_ACTIVE_BEFORE_RESTART_SECS = ${toString minActiveBeforeRestartSecs}

    SYSTEMCTL_BIN = "${systemctlBin}"

    EMPTY_STATE = {
        "consecutive_bad": 0,
        "last_restart_ts": 0,
        "restart_history": [],
        "last_status_ts": 0,
    }


    def load_state():
        if not STATE_FILE.exists():
            return dict(EMPTY_STATE)
        try:
            state = json.loads(STATE_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            return dict(EMPTY_STATE)
        merged = dict(EMPTY_STATE)
        merged.update(state)
        return merged


    def save_state(s):
        tmp = STATE_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(s) + "\n")
        tmp.replace(STATE_FILE)


    def get_frigate_service_state(now):
        try:
            proc = subprocess.run(
                [SYSTEMCTL_BIN, "show", "frigate.service",
                 "--property=ActiveState",
                 "--property=SubState",
                 "--property=ActiveEnterTimestampMonotonic"],
                capture_output=True, text=True, timeout=10,
            )
        except (subprocess.TimeoutExpired, OSError) as e:
            return None, f"systemctl_show_failed:{type(e).__name__}:{e}"
        if proc.returncode != 0:
            return None, f"systemctl_show_failed:rc={proc.returncode}:{proc.stderr.strip()}"

        fields = {}
        for line in proc.stdout.splitlines():
            key, sep, value = line.partition("=")
            if sep:
                fields[key] = value

        active_state = fields.get("ActiveState", "unknown")
        sub_state = fields.get("SubState", "unknown")
        active_enter_us = int(fields.get("ActiveEnterTimestampMonotonic") or 0)
        active_age = 0
        if active_enter_us > 0:
            try:
                uptime = float(Path("/proc/uptime").read_text().split()[0])
                active_age = max(0, int(uptime - active_enter_us / 1_000_000))
            except (OSError, IndexError, ValueError):
                active_age = 0
        return {
            "active_state": active_state,
            "sub_state": sub_state,
            "active_age": active_age,
            "now": int(now),
        }, None


    def sigkill_frigate():
        return subprocess.run(
            [SYSTEMCTL_BIN, "kill", "--kill-who=all",
             "--signal=SIGKILL", "frigate.service"],
            capture_output=True,
            text=True,
            check=False,
        )


    def main():
        STATE_DIR.mkdir(parents=True, exist_ok=True)

        if not STATUS_FILE.exists():
            print("no status file yet")
            return 0

        try:
            status = json.loads(STATUS_FILE.read_text())
        except (json.JSONDecodeError, OSError) as e:
            print(f"bad status file: {e}", file=sys.stderr)
            return 0

        now = time.time()
        age = now - status.get("ts", 0)
        if age > MAX_STATUS_AGE_SECS:
            print(f"status stale ({age:.0f}s old); probe may be broken")
            return 0

        state = load_state()
        verdict = status.get("verdict", "unknown")
        healthy = verdict == "healthy"
        status_ts = int(status.get("ts", 0) or 0)

        if healthy:
            if state["consecutive_bad"] > 0:
                print(f"healthy; resetting consecutive_bad "
                      f"({state['consecutive_bad']} -> 0)")
            state["consecutive_bad"] = 0
            state["last_status_ts"] = status_ts
            save_state(state)
            return 0

        service_state, service_err = get_frigate_service_state(now)
        if service_err is not None:
            print(f"{service_err}; not restarting", file=sys.stderr)
            return 2
        if (service_state["active_state"], service_state["sub_state"]) != ("active", "running"):
            if state["consecutive_bad"] > 0:
                print(f"frigate not active/running ({service_state}); "
                      f"resetting consecutive_bad ({state['consecutive_bad']} -> 0)")
            else:
                print(f"frigate not active/running ({service_state}); not restarting")
            state["consecutive_bad"] = 0
            state["last_status_ts"] = status_ts
            save_state(state)
            return 0
        if service_state["active_age"] < MIN_ACTIVE_BEFORE_RESTART_SECS:
            if state["consecutive_bad"] > 0:
                state["consecutive_bad"] = 0
            print(f"frigate active for only {service_state['active_age']}s "
                  f"(< {MIN_ACTIVE_BEFORE_RESTART_SECS}s); not restarting")
            state["last_status_ts"] = status_ts
            save_state(state)
            return 0

        if status_ts <= state["last_status_ts"]:
            print(f"already processed status ts={status_ts}; not incrementing "
                  f"consecutive_bad={state['consecutive_bad']}")
            return 0

        state["consecutive_bad"] += 1
        state["last_status_ts"] = status_ts

        if state["consecutive_bad"] < CONSECUTIVE_BAD_THRESHOLD:
            print(f"bad verdict={verdict} consecutive_bad="
                  f"{state['consecutive_bad']}/{CONSECUTIVE_BAD_THRESHOLD}; "
                  f"not yet restarting")
            save_state(state)
            return 0

        since_last = now - state["last_restart_ts"]
        if since_last < COOLDOWN_SECS:
            print(f"cooldown active ({since_last:.0f}s of {COOLDOWN_SECS}s); "
                  f"not restarting")
            save_state(state)
            return 0

        recent = [t for t in state["restart_history"] if now - t < WINDOW_SECS]
        if len(recent) >= MAX_RESTARTS_IN_WINDOW:
            print(f"rate limit: {len(recent)} restarts in last "
                  f"{WINDOW_SECS // 3600}h; not restarting — operator action needed",
                  file=sys.stderr)
            save_state(state)
            return 2

        entry = {
            "ts": int(now),
            "trigger": verdict,
            "status": status,
            "consecutive_bad": state["consecutive_bad"],
        }
        print(f"RESTART trigger={verdict} status={status}")
        with RESTART_LOG.open("a") as f:
            f.write(json.dumps(entry) + "\n")
        kill = sigkill_frigate()
        if kill.returncode != 0:
            print(f"systemctl kill failed rc={kill.returncode}: "
                  f"{kill.stderr.strip()}", file=sys.stderr)
            save_state(state)
            return 2

        state["consecutive_bad"] = 0
        state["last_restart_ts"] = int(now)
        state["restart_history"] = recent + [int(now)]
        save_state(state)
        return 0


    if __name__ == "__main__":
        sys.exit(main())
  '';

  status = pkgs.writeShellApplication {
    name = "frigate-watchdog-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -eu

      echo "== frigate.service =="
      systemctl --no-pager --full status frigate.service || true

      echo
      echo "== watchdog timers =="
      systemctl --no-pager --full status \
        frigate-watchdog-probe.timer \
        frigate-watchdog-act.timer || true

      echo
      echo "== latest status =="
      if [ -f ${stateDir}/status.json ]; then
        cat ${stateDir}/status.json
      else
        echo "no ${stateDir}/status.json yet"
      fi

      echo
      echo "== actor state =="
      if [ -f ${stateDir}/state.json ]; then
        cat ${stateDir}/state.json
      else
        echo "no ${stateDir}/state.json yet"
      fi

      echo
      echo "== restart log =="
      if [ -f ${stateDir}/restarts.log ]; then
        tail -n 20 ${stateDir}/restarts.log
      else
        echo "no ${stateDir}/restarts.log yet"
      fi
    '';
  };
in
{
  # Let frigate's own grace+force-shutdown path run to completion (~30s
  # worst case observed during a wedged stop). 45s gives that headroom
  # plus a real backstop if frigate's self-shutdown is itself ever wedged.
  # The watchdog SIGKILLs directly when it detects the wedge state, so
  # this timeout doesn't gate watchdog recovery — only operator-initiated
  # restarts and nixos-rebuild deploys.
  systemd.services.frigate.serviceConfig.TimeoutStopSec = "45s";

  # State dir: status.json + state.json + restarts.log live here. Readable
  # by anyone (status is benign), writable by root (which both timers run as).
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root -"
  ];

  environment.systemPackages = [ status ];

  systemd.services.frigate-watchdog-probe = {
    description = "Frigate health probe (writes ${stateDir}/status.json)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${probe}/bin/frigate-watchdog-probe";
      # root: needs to read systemd journal and run ss without group plumbing.
      User = "root";
      # The probe returns exit 1 to signal "unhealthy" (useful for journal grep
      # and act-script chaining), but we don't want systemd to mark the unit
      # failed every time — that masks real unit failures (Python crash, etc.)
      # and trips nixos-rebuild's activation script. Treat 0 and 1 as success.
      SuccessExitStatus = "0 1";
      # Light hardening — probe touches network (localhost), journal, and ss.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ stateDir ];
      PrivateTmp = true;
    };
  };

  systemd.timers.frigate-watchdog-probe = {
    description = "Run frigate health probe every 60s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # OnActiveSec (relative to timer activation) — first fire 60s after the
      # timer comes up. On deploy that gives frigate's restart time to settle;
      # on boot it gives the rest of the system the same headroom. Using
      # OnBootSec would have meant "fire 60s after boot time" which is already
      # in the past for a long-running box and would fire immediately on a
      # deploy that adds the timer.
      OnActiveSec = "60s";
      OnUnitActiveSec = "60s";
      AccuracySec = "1s";
    };
  };

  systemd.services.frigate-watchdog-act = {
    description = "Frigate watchdog actor (SIGKILLs wedged frigate)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${act}/bin/frigate-watchdog-act";
      User = "root"; # systemctl kill needs root or polkit
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ stateDir ];
      PrivateTmp = true;
    };
  };

  systemd.timers.frigate-watchdog-act = {
    description = "Run frigate watchdog act every 60s, offset 30s from probe";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # First fire 90s after the timer comes up — 30s after the first probe
      # has written status.json. Subsequent runs every 60s.
      OnActiveSec = "90s";
      OnUnitActiveSec = "60s";
      AccuracySec = "1s";
    };
  };
}
