{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Backend-only role: bitcoind + fulcrum + ZMQ sequence publisher,
  # exposed on the WireGuard mesh for albatross's frigate-edge. No
  # frigate process here, no TLS, no public Electrum endpoint — that's
  # albatross's job (HEL1-DC6, same metro as finney's HEL1-DC9 so RPC
  # latency stays sub-1 ms).
  #
  # The HMAC below matches the `bitcoind-rpc-creds.age` plaintext on
  # albatross (the rpcauth password is one-way derived; only the
  # plaintext is secret). Same HMAC as kingfisher had — let albatross
  # cut over without re-encrypting its credential file.
  services.bitcoind-backend = {
    enable = true;
    bindAddress = "10.42.0.3";
    interface = "wg0";
    allowedPeers = [ "10.42.0.2/32" ];
    rpcAuth = {
      user = "frigate-edge";
      passwordHMAC = "bec2842f5d4d3451316cc22f5db6560c$804448c1fd845e4160f5e6cc182b8250d5324679b9372e817fdb37c42ea71cc9";
    };
  };

  # Operator pattern: add josie to the `bitcoin` group so `bitcoin-cli`
  # works without `sudo -u bitcoin`. Host-specific because the operator
  # name varies per box.
  nix-bitcoin.operator = {
    enable = true;
    name = "josie";
  };

  # Bootstrap toggle: this preset is being applied to a box that already
  # has 766 GB of bitcoind state on tank/bitcoind (good — preserved) but
  # no fulcrum data yet. We seed tank/fulcrum from kingfisher via
  # `zfs send | zfs recv` AFTER the user/group on finney exists, so the
  # post-recv chown can target the local fulcrum UID (numerically
  # different from kingfisher's). Hold fulcrum dormant until the recv
  # and chown land — a half-baked /var/lib/fulcrum starts fulcrum on
  # an empty/partial state and either crash-loops or corrupts.
  #
  # autoUpgrade is paused for the same window: an hourly rebuild
  # firing during the recv would un-do the `wantedBy=[]` (since the
  # currently-checked-out main doesn't have these toggles) and start
  # fulcrum on an in-flight dataset. Albatross learned this the hard
  # way during its zfs-recv bootstrap (commit 84f3e8b).
  #
  # Lift both toggles together once `chown -R fulcrum:fulcrum
  # /var/lib/fulcrum` has run and `zfs list tank/fulcrum` shows the
  # expected USED size — then the next nixos-rebuild starts fulcrum
  # normally with the imported index and autoUpgrade resumes.
  systemd.services.fulcrum.wantedBy = lib.mkForce [ ];
  system.autoUpgrade.enable = lib.mkForce false;
}
