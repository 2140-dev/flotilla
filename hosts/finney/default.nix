{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "finney";

  # Used by kingfisher's `josie` to reach finney for ZFS replication
  # (zrepl-style backups, ad-hoc `zfs send`).
  users.users.josie.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC6yGOCsg6i2SAl/dNnXlWq87Q/ecWF2VaVsz9K71at josie@kingfisher"
  ];
}
