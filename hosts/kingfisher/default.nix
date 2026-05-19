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
    ./gpu.nix
    ./frigate.nix
    ./wireguard.nix
  ];

  networking.hostName = "kingfisher";

  # Secondary operator key (josie's other workstation).
  users.users.josie.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCpFamyP8ty8y7svPT2y2agdGgjRJQYZJk/v8/JyF8uMYED0KNecyyiqabGzX//+yz2SgPuSSql3Qa9AU2hjPUJHNcQna+P6Gp/25Lm1ak/suiRRKcdjW1FX39No3teaVNfoEC+KTKfzLEt0if6DmlEqjEn8cYpC8lMcQtjCCwif4BYMlVhHToSXpYu6v1b9xchcRa7N9RPAUDk5V8VCHiaWaYoYWUOGQXX49XHrpgrwyMe4WRgsKQhJwbW5HCAQl2D3sdMxPJVHBpor75iI4mPOxuQfLfDiM6hcQ1isrCNjpDyBac7S2Rv29Lu0E9Z9hzqWwCyM0GlimQIDkLWnxNrhldW4CUBQbdi5irUiSrcsMtbESbdBPi3Jn9clabIgGP8rCyXJSKLu3CfrT14OaAV+rJbUyaPfWQtkO/cfCiMVlOdr12XnexM/koE/I5Vw5gHcprUffDFunZm0pXYFVol+a45XACmIXYSSLLrM8/VSkfAYSMNZNfT0udUyq6dlw4RbA0aDzTDJtMS5NHC0Iw/Og4Y2nY6XPEke9Uem1nBHtZGsb+RrMC1ozyxSvoTzdW7jnkQQm9sQOc38dCDOrmQ1sv00EYBc6MPWOHWnjmjidd2IOSA1YOnwRGMPCTMOXLlaMCEZJRLIPwoiLtpCm97MF2xJc2bQ/M8iselbEgO5Q== macgyver@home"
  ];
}
