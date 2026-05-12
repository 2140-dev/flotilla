{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Same public hostname as kingfisher. Once both boxes are live this
  # is the load-balancing seam — either DNS round-robin on the A/AAAA
  # records or HAProxy fronting both backends. While only kingfisher
  # holds the records, albatross's ACME issuance will fail (HTTP-01
  # needs DNS pointed at the host requesting the cert); plan for a
  # brief DNS swap during first install, or move to DNS-01 challenge
  # before adding the second backend.
  services.public-frigate = {
    enable = true;
    host = "frigate.2140.dev";
    tls.acmeEmail = "josie@2140.dev";
  };

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
}
