{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Edge-mode Frigate: TLS termination + ACME live here, the bitcoind /
  # fulcrum / ZMQ stack runs on finney (HEL1-DC9, sub-1 ms from this
  # box in HEL1-DC6) and is consumed over the private WireGuard mesh.
  # See ./wireguard.nix and ../_mesh.nix for the topology; backends
  # were previously on kingfisher (NBG, 26 ms) which made frigate's
  # mempool-init phase take ~47 minutes.
  services.frigate-edge = {
    enable = true;
    # Public hostname promoted from albatross.2140.dev to frigate.2140.dev
    # after DNS for frigate.2140.dev was moved here. ACME re-issues a
    # cert for the new SAN on the next activation; the postRun on the
    # _internal/frigate-tls-acme helper converts the lego output to
    # PKCS#8 so frigate's TLS loader accepts it.
    host = "frigate.2140.dev";
    tls.acmeEmail = "josie@2140.dev";

    backend = {
      bitcoind = {
        rpcUrl = "http://10.42.0.3:8332";
        authCredentialFile = config.age.secrets.bitcoind-rpc-creds.path;
        zmqSequenceEndpoint = "tcp://10.42.0.3:28336";
      };
      electrumUrl = "tcp://10.42.0.3:60001";
    };
  };

  # `user:password` consumed by frigate via systemd LoadCredential. The
  # matching `rpcauth=user:salt$hash` line lives on finney (the active
  # backend) in hosts/finney/backend.nix; the same HMAC is also present
  # on kingfisher under exposeBackends.rpcAuth.passwordHMAC so this
  # credential file works against either backend without re-encryption.
  # Mode 0440 + owner `frigate` so the frigate user (declared by the
  # bare frigate module) can read it for LoadCredential to pick up.
  age.secrets.bitcoind-rpc-creds = {
    file = ../../secrets/bitcoind-rpc-creds.age;
    owner = "frigate";
    mode = "0440";
  };

  # systemd starts services with a stripped environment that does not
  # inherit NixOS's interactive-shell GPU library path. Without this,
  # frigate's JVM dlopen of libOpenCL.so.1 fails and DuckDB's ufsecp
  # extension silently falls back to CPU.
  systemd.services.frigate.environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";

  services.frigate.settings.scan = {
    # Use frigate's native default batch (300k) rather than the roost
    # preset's more conservative 200k. albatross's GPU has the compute
    # width + memory for the bigger kernels; one round of measurement
    # (200k @ 10c vs 500k @ 20c) didn't conclusively recommend a value,
    # so default to what upstream picked until we run a controlled sweep.
    batchSize = 300000;
    computeBackend = "GPU";
    dbThreads = 8;
    memoryLimit = "64GB";

    # First-cut guardrail against one public client queuing many expensive
    # silent-payment history scans on the shared DuckDB/GPU path.
    maxSubscriptions = 10;
  };

  networking.firewall.extraCommands = ''
    # Cap new public Electrum SSL connections per source so one crawler
    # cannot multiply Frigate's per-connection silent-payment limits.
    iptables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m connlimit --connlimit-above 10 --connlimit-mask 32 \
      --connlimit-saddr -j DROP
    ip6tables -w -I nixos-fw 1 -p tcp --syn --dport 50002 \
      -m connlimit --connlimit-above 10 --connlimit-mask 128 \
      --connlimit-saddr -j DROP
  '';
}
