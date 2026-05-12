{
  # 2× Samsung MZQL2960HCJR-00A07 (894 GB enterprise NVMe, PM9A3 family) in
  # ZFS mirror. Disk identifiers are pinned by serial via /dev/disk/by-id
  # so kernel renumbering (nvme0/nvme1 swapping) is harmless.
  #
  # Capacity note: ~866 GB usable after ZFS overhead. bitcoind+txindex
  # (~750 GB and growing) plus Fulcrum (~200 GB) is tight on this layout
  # — expect to revisit storage within 12-18 months. Options at that
  # point: add drives (Hetzner add-on), switch to raidz with extra
  # disks, or split bitcoind off to a separate host.
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZQL2960HCJR-00A07_S64FNNRYC01790";
        content = {
          type = "gpt";
          partitions = {
            # 1MB BIOS boot partition. Combined with GRUB's
            # efiInstallAsRemovable in roost.hetzner-bare-metal, Hetzner
            # UEFI finds the bootloader either via BIOS embed or the
            # EFI removable path — belt and suspenders.
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
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZQL2960HCJR-00A07_S64FNNRYC01792";
        content = {
          type = "gpt";
          # Single ESP on nvme0 (kingfisher/finney pattern). If nvme0
          # dies, recovery is one KVM session: boot rescue, zpool import
          # rpool, chroot, nixos-rebuild boot.
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

        # `local` for non-replicated bits (root, /nix). `safe` for state
        # worth keeping across a reinstall — service data lives here.
        # No legacy electrs dataset: this host is born on Fulcrum.
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
              # DuckDB writes large sequential blocks during the secp
              # scan batches; 1M records cut metadata overhead and
              # compress better than the 128k default.
              recordsize = "1M";
            };
          };
          "safe/bitcoind" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/bitcoind";
            options = {
              mountpoint = "legacy";
              # Block files are large sequential writes; 1M records cut
              # metadata overhead and compress better than 128k.
              recordsize = "1M";
            };
          };
          "safe/fulcrum" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/fulcrum";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
