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
#        cd secrets && nix run github:ryantm/agenix -- -e bitcoind-rpcauth.age
#   5. Reference them from a host module via `age.secrets.<name>.file = ./secrets/<name>.age;`.
let
  josie = "age1...REPLACE_ME_WITH_YOUR_AGE_PUBKEY";
  finney = "ssh-ed25519 AAAA...REPLACE_ME_WITH_HOST_KEY_AFTER_FIRST_BOOT";
  kingfisher = "ssh-ed25519 AAAA...REPLACE_ME_WITH_HOST_KEY_AFTER_FIRST_BOOT";
in
{
  # Examples — uncomment and create the .age files when wiring services:
  # "bitcoind-rpcauth.age".publicKeys = [ josie kingfisher ];
  # "wireguard-finney.age".publicKeys = [ josie finney ];
}
