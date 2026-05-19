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
}
