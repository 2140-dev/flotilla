{
  config,
  lib,
  pkgs,
  ...
}:

{
  # NVIDIA's kernel-side driver is unfree; their open kernel module
  # (Turing+, including Ada) is MIT-licensed but the userspace stack isn't.
  nixpkgs.config.allowUnfree = true;

  # Triggers nvidia driver build/load even on a headless box. The option
  # name is misleading — xserver itself is not enabled.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # RTX 4000 SFF Ada Generation supports the open kernel module.
    open = true;
    modesetting.enable = true;
    nvidiaSettings = false; # no GUI tools needed
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # OpenCL ICD discovery. Frigate's DuckDB ufsecp extension uses OpenCL;
  # the NVIDIA driver package supplies its ICD automatically once
  # hardware.graphics is on.
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    clinfo # `clinfo` to verify OpenCL ICD wired correctly
    nvtopPackages.nvidia # nvtop for GPU monitoring
  ];
}
