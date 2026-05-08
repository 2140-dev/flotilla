{
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            # 1MB BIOS boot partition for GRUB's BIOS-mode embedding.
            # Combined with grub.efiInstallAsRemovable, gives Hetzner UEFI
            # two ways to find the bootloader (BIOS embed + EFI fallback).
            bios = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };

      nvme1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          # No ESP on nvme1 — single ESP on nvme0 (matching finney's pattern).
          # If nvme0 dies, recovery is one KVM session: boot rescue,
          # `zpool import rpool`, chroot, `nixos-rebuild boot`.
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool";
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          mountpoint = "none";
          canmount = "off";
        };
        options = {
          ashift = "12";
          autotrim = "on";
        };

        # Same two-tier pattern as finney: `local` for non-replicated bits
        # (root, /nix), `safe` for state worth keeping. Frigate's DuckDB
        # index lives under `safe` so it survives a disk failure — though
        # it's also re-derivable from a chain rescan.
        datasets = {
          "local" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };

          "safe" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          "safe/var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options.mountpoint = "legacy";
          };
          "safe/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };
          "safe/frigate" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/frigate";
            options = {
              mountpoint = "legacy";
              # DuckDB writes large sequential blocks during the secp scan
              # batches; 1M records cut metadata overhead and compress
              # better than the 128k default.
              recordsize = "1M";
            };
          };
          "safe/bitcoind" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/bitcoind";
            options = {
              mountpoint = "legacy";
              # Bitcoin block files are large sequential writes; 1M records
              # cut metadata overhead and compress better than the 128k default.
              recordsize = "1M";
            };
          };
          "safe/electrs" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/electrs";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
