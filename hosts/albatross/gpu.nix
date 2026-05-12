{
  config,
  lib,
  pkgs,
  ...
}:

{
  # NVIDIA's kernel-side driver is unfree; the open kernel module
  # (Turing+) is MIT-licensed but the userspace stack isn't.
  nixpkgs.config.allowUnfree = true;

  # Triggers nvidia driver build/load even on a headless box. The option
  # name is misleading — xserver itself is not enabled.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # RTX PRO 6000 Blackwell Max-Q Workstation Edition (GB202, PCI ID
    # 10de:2bb4). Blackwell requires the open kernel module.
    open = true;
    modesetting.enable = true;
    nvidiaSettings = false; # no GUI tools needed
    # Blackwell requires driver 570+. nixpkgs' `production` channel
    # tracks NVIDIA's production stream; on nixos-unstable as of
    # mid-2026 it carries 570.x+. If a future nixpkgs bump regresses
    # this to a pre-570 release, switch to `nvidiaPackages.latest` or
    # pin a specific version.
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # OpenCL ICD discovery. Frigate's DuckDB ufsecp extension uses OpenCL;
  # the NVIDIA driver package supplies its ICD automatically once
  # hardware.graphics is on.
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    clinfo # verify OpenCL ICD wired correctly
    nvtopPackages.nvidia # nvtop for GPU monitoring
  ];
}
