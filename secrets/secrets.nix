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
  josie = "age1jf8np2gw2wkd0k46x4z3plr47jz0kqvjker63jh2xqqjqpszcedsg2e6ug";
  finney = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJrlkSFtMHRfnVZwdQUZmID0RSmUTGlLQ+eP8PpGir06 root@finney";
  kingfisher = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB2j+A4rvxr+5JIP4XrRqAI3uHUOriAPpiDSc8F+izAG root@kingfisher";
  albatross = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAPnn6DYBcz7nkpnOniTfwLtncQ8JlzYSjkFLd5uL5o3 root@albatross";
in
{
  # `user:password` for the bitcoind RPC user that frigate-edge on
  # albatross uses to authenticate to its backend's bitcoind. The
  # matching rpcauth HMAC is committed in hosts/finney/backend.nix
  # (the active backend post-cutover) and hosts/kingfisher/frigate.nix
  # (the original backend) — same HMAC in both, so this single
  # credential authenticates against either.
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
  "wireguard-finney.age".publicKeys = [
    josie
    finney
  ];
}
