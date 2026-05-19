{ config, ... }:

{
  imports = [ ../_mesh.nix ];

  # Encrypted private key. Agenix decrypts to /run/agenix/wireguard-finney
  # at activation; the wireguard module reads it as `privateKeyFile`. Mode
  # 0400 keeps it root-only on disk.
  age.secrets.wireguard-finney = {
    file = ../../secrets/wireguard-finney.age;
    mode = "0400";
  };

  services.roost.wireguard-mesh = {
    enable = true;
    thisHost = "finney";
    privateKeyFile = config.age.secrets.wireguard-finney.path;
    meshCidr = "10.42.0.0/24";
  };
}
