{ ... }:

# Shared peer definitions for the private WireGuard mesh between
# kingfisher (the all-in-one frigate node) and albatross (the
# frigate-edge consumer). Imported by both hosts' wireguard.nix so the
# `peers` block is one place. Adding a third node is a one-line edit
# here plus that node's own `thisHost` + private-key wiring.
#
# The public keys below are PLACEHOLDERS — wireguard treats them as
# opaque strings during build, so the system closure evaluates fine,
# but `wg set` rejects them at activation. Replace before deploying:
#   1. `wg genkey | tee priv | wg pubkey > pub` per host
#   2. paste the public key into the matching entry here
#   3. `agenix -e secrets/wireguard-<host>.age` and paste the private
#      key into the file
#
# Endpoint IPs are kingfisher's and albatross's public addresses. WG
# resolves these once at interface setup; if either box's IP rotates
# the matching entry below has to update too.

{
  services.roost.wireguard-mesh.peers = {
    kingfisher = {
      publicKey = "PLACEHOLDER_KINGFISHER_WG_PUBKEY=";
      endpoint = "136.243.9.246:51820";
      meshIp = "10.42.0.1";
    };
    albatross = {
      publicKey = "PLACEHOLDER_ALBATROSS_WG_PUBKEY=";
      endpoint = "46.62.185.45:51820";
      meshIp = "10.42.0.2";
    };
  };
}
