{ config, ... }:

{
  imports = [ ../_mesh.nix ];

  # Encrypted private key. Agenix decrypts to /run/agenix/wireguard-albatross
  # at activation; the wireguard module reads it as `privateKeyFile`. Mode
  # 0400 keeps it root-only on disk.
  age.secrets.wireguard-albatross = {
    file = ../../secrets/wireguard-albatross.age;
    mode = "0400";
  };

  services.roost.wireguard-mesh = {
    enable = true;
    thisHost = "albatross";
    privateKeyFile = config.age.secrets.wireguard-albatross.path;
    meshCidr = "10.42.0.0/24";
  };
}
