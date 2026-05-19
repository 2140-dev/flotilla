{ ... }:

# Shared peer definitions for the private WireGuard mesh between
# kingfisher (all-in-one frigate node), albatross (frigate-edge
# consumer), and finney (bitcoind-backend for albatross). Imported by
# each host's wireguard.nix so the `peers` block lives in one place.
# Adding a fourth node is a one-line edit here plus that node's own
# `thisHost` + private-key wiring.
#
# Endpoints are each host's public address. WG resolves these once at
# interface setup; if a box's IP rotates the matching entry has to
# update too. Private keys matching the public keys below live in
# secrets/wireguard-<host>.age, encrypted to `josie` and that host's
# own SSH key.

{
  services.roost.wireguard-mesh.peers = {
    kingfisher = {
      publicKey = "65eBW/IfinjLj7Q9HBnw+CBeEAx/6zaMVDejs+Vxb2o=";
      endpoint = "136.243.9.246:51820";
      meshIp = "10.42.0.1";
    };
    albatross = {
      publicKey = "BZFpBTwYt3RUPFkIMQIrXZgkMDGryaae/empkoEiehE=";
      endpoint = "46.62.185.45:51820";
      meshIp = "10.42.0.2";
    };
    finney = {
      publicKey = "L/7QR3ANOD+QmExD/m63tBL8sDpK2h2zQWrja4cozS4=";
      endpoint = "65.21.237.160:51820";
      meshIp = "10.42.0.3";
    };
  };
}
