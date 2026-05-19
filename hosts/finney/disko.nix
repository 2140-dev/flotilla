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
          # No ESP on this disk — systemd-boot doesn't natively mirror to a
          # second ESP. If nvme0 dies, recovery is one KVM session: boot
          # rescue, `zpool import rpool`, chroot, `nixos-rebuild boot`.
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool";
            };
          };
        };
      };

      # nvme2 (1.9TB Samsung) hosts the `tank` pool — bitcoind's chain
      # data and txindex live on tank/bitcoind, fulcrum's index on
      # tank/fulcrum. Single-device pool: the bitcoind chain is
      # reconstructable from network, so we accept the disk as a single
      # point of failure rather than burning a second 1.9 TB NVMe on a
      # mirror.
      nvme2 = {
        type = "disk";
        device = "/dev/nvme2n1";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "tank";
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

        # Two-tier dataset layout: `local` for things that don't need
        # snapshot/replication (root, /nix), `safe` for state worth keeping
        # (logs, home).
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
        };
      };

      # Bitcoin backend storage. tank/bitcoind already exists with ~766 GB
      # of mainnet chain + txindex from the prior single-tenant layout —
      # disko on `nixos-rebuild switch` only generates fileSystems mounts
      # for declared datasets; it does not recreate or wipe an existing
      # one. The dataset's runtime properties (mountpoint=legacy,
      # compression=zstd) already match what we declare here.
      tank = {
        type = "zpool";
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
        datasets = {
          "bitcoind" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/bitcoind";
            options.mountpoint = "legacy";
          };
          "fulcrum" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/fulcrum";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
