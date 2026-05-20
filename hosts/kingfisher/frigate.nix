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

  # frigate.2140.dev DNS now points at albatross — this box is a hot
  # standby keeping bitcoind/fulcrum/frigate state warm in case we
  # need to flip back. Bind the SSL listener to loopback so nothing
  # external can reach it; the existing ACME cert continues to work
  # until its next renewal (which will fail when lego can't HTTP-01
  # validate since DNS no longer routes here — address before then by
  # promoting back, renaming, or dropping the cert).
  services.frigate.ssl = lib.mkForce "ssl://127.0.0.1:50002";

  # systemd starts services with a stripped environment that does not
  # inherit NixOS's interactive-shell GPU library path. Without this,
  # frigate's JVM dlopen of libOpenCL.so.1 fails and DuckDB's ufsecp
  # extension silently falls back to CPU.
  systemd.services.frigate.environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
}
