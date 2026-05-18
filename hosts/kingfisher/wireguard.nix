{ config, ... }:

{
  imports = [ ../_mesh.nix ];

  # Encrypted private key. Agenix decrypts to /run/agenix/wireguard-kingfisher
  # at activation; the wireguard module reads it as `privateKeyFile`. Mode
  # 0400 keeps it root-only on disk.
  age.secrets.wireguard-kingfisher = {
    file = ../../secrets/wireguard-kingfisher.age;
    mode = "0400";
  };

  services.roost.wireguard-mesh = {
    enable = true;
    thisHost = "kingfisher";
    privateKeyFile = config.age.secrets.wireguard-kingfisher.path;
    meshCidr = "10.42.0.0/24";
  };
}
