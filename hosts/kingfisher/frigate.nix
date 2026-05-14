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

  # systemd starts services with a stripped environment that does not
  # inherit NixOS's interactive-shell GPU library path. Without this,
  # frigate's JVM dlopen of libOpenCL.so.1 fails and DuckDB's ufsecp
  # extension silently falls back to CPU.
  systemd.services.frigate.environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
}
