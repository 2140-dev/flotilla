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

    # Silent payments subscriptions per connection. Each one starts a scan
    # on the shared GPU.
    maxSubscriptions = 5;
  };

  # maxConnectionsPerIp matches the firewall's per-source cap below.
  # Loopback stays exempt, which the watchdog probe relies on.
  services.frigate.settings.limits = {
    maxConnections = 500;
    maxConnectionsPerIp = 6;
    silentPaymentsSubscribeBurst = 3;
    silentPaymentsSubscribeIntervalSeconds = 30;
  };

  # Per source (IPv4 address, IPv6 /64, matching frigate): at most 6
  # concurrent and 20 new connections a minute to the public port. The rate
  # cap stops clients reconnecting to reset frigate's per-session pacing.
  networking.firewall.extraCommands = ''
    iptables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m connlimit --connlimit-above 6 --connlimit-mask 32 \
      --connlimit-saddr -j DROP
    iptables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m hashlimit --hashlimit-name frigate-v4 --hashlimit-mode srcip \
      --hashlimit-srcmask 32 --hashlimit-above 20/minute --hashlimit-burst 20 \
      -j DROP
    ip6tables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m connlimit --connlimit-above 6 --connlimit-mask 64 \
      --connlimit-saddr -j DROP
    ip6tables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m hashlimit --hashlimit-name frigate-v6 --hashlimit-mode srcip \
      --hashlimit-srcmask 64 --hashlimit-above 20/minute --hashlimit-burst 20 \
      -j DROP
  '';

  # Under memory pressure the kernel kills frigate, not bitcoind or fulcrum;
  # the watchdog and Restart= bring it back.
  systemd.services.frigate.serviceConfig.MemoryMax = "28G";

  # Leave room for bitcoind, fulcrum and frigate in 62 GiB.
  boot.kernelParams = [ "zfs.zfs_arc_max=${toString (16 * 1024 * 1024 * 1024)}" ];
}
