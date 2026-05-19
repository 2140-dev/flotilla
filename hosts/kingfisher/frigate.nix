{
  config,
  lib,
  pkgs,
  ...
}:

{
  # roost.nixosModules.default (the batteries-included path) brings in
  # nix-bitcoin, configures bitcoind+fulcrum+frigate, and terminates
  # Electrum-over-TLS in nginx with ACME on the configured host. All
  # this host needs is identity (DNS) and an ACME contact email.
  services.public-frigate = {
    enable = true;
    host = "frigate.2140.dev";
    tls.acmeEmail = "josie@2140.dev";

    # Expose bitcoind RPC + ZMQ + fulcrum on the WireGuard mesh interface
    # so albatross can run frigate-edge against this stack instead of
    # carrying its own ~950 GB chain copy. Interface-scoped firewall
    # keeps these ports unreachable from the public internet.
    #
    # The HMAC below is committed (one-way derived from the password);
    # the plaintext lives in secrets/bitcoind-rpc-creds.age on albatross.
    # See modules/wireguard-mesh.nix for the mesh topology and
    # hosts/_mesh.nix for the peer registry.
    exposeBackends = {
      enable = true;
      bindAddress = "10.42.0.1";
      interface = "wg0";
      allowedPeers = [ "10.42.0.2/32" ];
      rpcAuth = {
        user = "frigate-edge";
        passwordHMAC = "bec2842f5d4d3451316cc22f5db6560c$804448c1fd845e4160f5e6cc182b8250d5324679b9372e817fdb37c42ea71cc9";
      };
    };
  };

  # Operator pattern: add josie to the `bitcoin` group so `bitcoin-cli`
  # works directly without `sudo -u bitcoin`. Host-specific because the
  # operator name varies per box.
  nix-bitcoin.operator = {
    enable = true;
    name = "josie";
  };

  # Smaller scan batch than the preset's default. Shorter per-scan
  # latency at the cost of slightly higher framing overhead — a
  # comfortable middle ground for kingfisher's workload.
  services.frigate.settings.scan.batchSize = 100000;

  # Fulcrum defaults `max_clients_per_ip = 12`; with concurrent benchmark
  # clients (each opening a fresh frigate session that itself opens an
  # upstream fulcrum connection over loopback) we exceed the cap and
  # refused connections cascade into VersionNotNegotiated / Internal
  # error responses to the benchmark. Raise the per-IP cap; the public
  # TLS endpoint is the only externally reachable surface — fulcrum is
  # only reachable from this box's own frigate (127.0.0.1) and
  # albatross over wg0, so a higher cap is harmless.
  services.fulcrum.extraConfig = ''
    max_clients_per_ip = 50
  '';

  # systemd starts services with a stripped environment that does not
  # inherit NixOS's interactive-shell GPU library path. Without this,
  # frigate's JVM dlopen of libOpenCL.so.1 fails and DuckDB's ufsecp
  # extension silently falls back to CPU.
  systemd.services.frigate.environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
}
