{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Own hostname for now (rather than sharing kingfisher's
  # frigate.2140.dev). Each backend self-issues its own cert via
  # HTTP-01 — no DNS-01 wiring and no shared-cert coordination.
  # Future load-balancing work will move both back behind a single
  # hostname, fronted by a third host doing TCP/SNI passthrough.
  services.public-frigate = {
    enable = true;
    host = "albatross.2140.dev";
    tls.acmeEmail = "josie@2140.dev";
  };

  # Add josie to the `bitcoin` group so `bitcoin-cli` works directly
  # without `sudo -u bitcoin`. Operator name varies per box, so this
  # stays per-host.
  nix-bitcoin.operator = {
    enable = true;
    name = "josie";
  };

  # 48-thread Xeon Gold 5412U with 256 GB RAM and a Blackwell RTX PRO
  # 6000 (96 GB VRAM). The roost preset's default dbCache of 4 GB
  # underuses this box badly during IBD; bump it for faster initial
  # sync. Drop back after sync if memory pressure shows up elsewhere.
  services.bitcoind.dbCache = lib.mkForce 16384;

  # systemd starts services with a stripped environment that does not
  # inherit NixOS's interactive-shell GPU library path. Without this,
  # frigate's JVM dlopen of libOpenCL.so.1 fails and DuckDB's ufsecp
  # extension silently falls back to CPU.
  systemd.services.frigate.environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";

  # batchSize tuning is deferred: this GPU is roughly an order of
  # magnitude more capable than kingfisher's RTX 4000 SFF Ada and the
  # right value will only be visible after a real scan. The module
  # default (300_000) is the starting point.

  # BOOTSTRAP: keep the data-bearing services from autostarting on the
  # first boot so /var/lib/{bitcoind,fulcrum,frigate} can be populated
  # via `zfs recv` from kingfisher without racing live writes. The
  # users/groups still get created (those come from the modules' user
  # definitions, independent of wantedBy), so the post-recv chown
  # step has somebody to chown to.
  #
  # Also disable autoUpgrade for the duration: the seeding workflow
  # destroys the placeholder datasets before recv, which would leave
  # mount units in a failed state until recv lands. An hourly rebuild
  # firing during that window risks compounding the breakage and
  # killed albatross on the first attempt.
  #
  # Remove this block once the import is complete and push; the next
  # nixos-rebuild will land services in multi-user.target normally,
  # they will start with the imported state, and autoUpgrade resumes
  # polling.
  systemd.services.bitcoind.wantedBy = lib.mkForce [ ];
  systemd.services.fulcrum.wantedBy = lib.mkForce [ ];
  systemd.services.frigate.wantedBy = lib.mkForce [ ];
  system.autoUpgrade.enable = lib.mkForce false;
}
