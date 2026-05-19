{ ... }:

# Shared peer definitions for the private WireGuard mesh between
# kingfisher (the all-in-one frigate node) and albatross (the
# frigate-edge consumer). Imported by both hosts' wireguard.nix so the
# `peers` block is one place. Adding a third node is a one-line edit
# here plus that node's own `thisHost` + private-key wiring.
#
# Endpoint IPs are kingfisher's and albatross's public addresses. WG
# resolves these once at interface setup; if either box's IP rotates
# the matching entry below has to update too. The private keys
# matching the public keys below live in secrets/wireguard-<host>.age,
# encrypted to both `josie` and the host's own SSH key.

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
  };
}
