# agenix recipient registry. Each `<name>.age` in this directory is a
# separate file encrypted to a list of public keys (here, plus the host
# SSH key for whichever box decrypts it at activation).
#
# Bootstrap order:
#   1. Install NixOS via nixos-anywhere (no secrets needed yet).
#   2. After first boot, scrape the host SSH ed25519 pubkey:
#        ssh josie@<host>.2140.dev cat /etc/ssh/ssh_host_ed25519_key.pub
#      Paste it into the matching variable below.
#   3. Generate your own age key on this Mac if you don't have one:
#        nix run github:ryantm/agenix -- --identity edit-key
#      and paste its public form into `josie` below.
#   4. Encrypt secrets:
#        cd secrets && nix run github:ryantm/agenix -- -e <name>.age
#   5. Reference them from a host module via `age.secrets.<name>.file = ./secrets/<name>.age;`.
let
  josie = "age1...REPLACE_ME_WITH_YOUR_AGE_PUBKEY";
  finney = "ssh-ed25519 AAAA...REPLACE_ME_WITH_HOST_KEY_AFTER_FIRST_BOOT";
  kingfisher = "ssh-ed25519 AAAA...REPLACE_ME_WITH_HOST_KEY_AFTER_FIRST_BOOT";
  albatross = "ssh-ed25519 AAAA...REPLACE_ME_WITH_HOST_KEY_AFTER_FIRST_BOOT";
in
{
  # `user:password` for the bitcoind RPC user that frigate-edge on
  # albatross uses to authenticate to kingfisher's bitcoind. The
  # corresponding rpcauth HMAC lives in
  # hosts/kingfisher/frigate.nix (services.public-frigate.exposeBackends.rpcAuth.passwordHMAC).
  "bitcoind-rpc-creds.age".publicKeys = [
    josie
    albatross
  ];

  # Per-host WireGuard private keys. Each one only needs to decrypt on
  # its own host plus josie (so josie can re-encrypt if needed).
  "wireguard-kingfisher.age".publicKeys = [
    josie
    kingfisher
  ];
  "wireguard-albatross.age".publicKeys = [
    josie
    albatross
  ];
}
