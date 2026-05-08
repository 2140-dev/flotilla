{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Pinned at install. Never bump — controls migration semantics for
  # stateful services (NixOS releases sometimes change defaults that
  # affect existing on-disk data).
  system.stateVersion = "25.11";

  networking = {
    domain = "2140.dev";

    # ZFS requires a stable 8-hex-char host id. Derived from the FQDN so
    # it follows the host config rather than living as a magic constant.
    hostId = builtins.substring 0 8 (
      builtins.hashString "sha256" "${config.networking.hostName}.${config.networking.domain}"
    );

    useDHCP = lib.mkDefault true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  time.timeZone = "UTC";

  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs.devNodes = "/dev/disk/by-id";
    zfs.forceImportRoot = false;
  };

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  users.mutableUsers = false;
  users.users.josie = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    # Always-present operator key (josie's primary laptop). Hosts add
    # additional keys (replication peers, secondary workstations) via
    # `users.users.josie.openssh.authorizedKeys.keys = [ ... ];` — the
    # NixOS module system merges list values, so they accumulate.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCoOq/s5Up2Fo8l2HJbxA786A4F8pc6EYbWI0271ev1mJ37l/IqMiYRgG6MkAIbH1nvD7OTLwKOP+0xKq3YHlEOhfrcRz7/qcN51PfS6FPai4VVklCx6mqfraPzOW1AOEvRVNhY661mc86yij9+dSu0iN/9ZMxM+uKNYZDDjey4J9oQUtiENy7kWeT4GDYZfrjo1+r08LYAH8sXlWtFlBI2uGtsJUWI39g6Rc1F0jIxXMMM4FiHofLGqCchOHnBBy2EmFAIXuddAfZ3Z4TNJDvFr52v8eOUxRsLhwUYd5OFRTyxVDQGJmpYjvuyT7WukwnSLAAYjRs5qXLV4BMfrtsKF6Ipw1rg3VJFiEe52EQdD4a53ssHmBTLM7r3s+FfU/lipd7y2dN9ZqDTWL3y2Cs2Z+eE8dBzpGpqtYCZz2f3AeB078dh9uPusdJaNZJDZZQCHsalXDln78wgDr43HhbCe+iMepLEWx7I+msd3VEecaiv+kcI5bY6FztPtxHz3pM= josibake@josies-Laptop.local"
    ];
  };

  programs.fish.enable = true;

  # SSH key auth is the only login path; no password to prompt for under sudo.
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = [
    pkgs.git
    pkgs.htop
    pkgs.tmux
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    substituters = [ "https://2140-dev.cachix.org" ];
    trusted-public-keys = [
      "2140-dev.cachix.org-1:0brdoxVmXjL5udKuI+vXXwdEjPInGQKjCiyJLReZBt8="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Pull-based deploy. Each host polls flotilla's main branch hourly and
  # applies its own configuration via `nixos-rebuild switch`. The flake
  # lockfile (committed to main) pins all inputs, so what CI tested is
  # exactly what activates here. Failed builds leave the previous config
  # in place; nothing destructive happens on a broken push.
  system.autoUpgrade = {
    enable = true;
    flake = "github:2140-dev/flotilla#${config.networking.hostName}";
    flags = [ "-L" ];
    dates = "hourly";
    randomizedDelaySec = "10min";
  };
}
