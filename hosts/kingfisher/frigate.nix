{
  config,
  lib,
  pkgs,
  ...
}:

{
  # roost.nixosModules.default (the batteries-included path) brings in
  # nix-bitcoin, configures bitcoind+fulcrum+frigate, and terminates
  # Electrum-over-TLS with ACME on the configured host. All this host
  # needs is identity (DNS) and an ACME contact email.
  services.public-frigate = {
    enable = true;
    host = "frigate.2140.dev";
    tls.acmeEmail = "josie@2140.dev";
  };

  # Operator pattern: add josie to the `bitcoin` group so `bitcoin-cli`
  # works directly without `sudo -u bitcoin`. Host-specific because the
  # operator name varies per box.
  nix-bitcoin.operator = {
    enable = true;
    name = "josie";
  };

  # systemd starts services with a stripped environment that does not
  # inherit NixOS's interactive-shell GPU library path. Without this,
  # frigate's JVM dlopen of libOpenCL.so.1 fails and DuckDB's ufsecp
  # extension silently falls back to CPU.
  systemd.services.frigate.environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";

  services.frigate.settings.scan = {
    # Smaller than the default 300k to fit the RTX 4000's 20 GB of VRAM.
    batchSize = 100000;
    computeBackend = "GPU";
    dbThreads = 8;

    memoryLimit = "20GB";

    # First-cut guardrail against one public client queuing many expensive
    # silent-payment history scans on the shared DuckDB/GPU path.
    maxSubscriptions = 10;
  };

  # frigate 1.6 enforces its own connection gate. Match the firewall's
  # per-source cap below so both layers agree; the firewall stays as the
  # cheaper first line, dropping SYNs before they reach the JVM. Other
  # [limits] use upstream defaults (global 1000 sessions, silent payments
  # subscribe pacing of 10 burst then one per 10s); loopback stays exempt,
  # which the watchdog probe relies on.
  services.frigate.settings.limits.maxConnectionsPerIp = 6;

  networking.firewall.extraCommands = ''
    # Cap new public Electrum SSL connections per source so one crawler
    # cannot multiply Frigate's per-connection silent-payment limits.
    iptables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m connlimit --connlimit-above 6 --connlimit-mask 32 \
      --connlimit-saddr -j DROP
    ip6tables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m connlimit --connlimit-above 6 --connlimit-mask 128 \
      --connlimit-saddr -j DROP
  '';

  # Leave room for bitcoind, fulcrum and frigate in 62 GiB.
  boot.kernelParams = [ "zfs.zfs_arc_max=${toString (16 * 1024 * 1024 * 1024)}" ];
}
