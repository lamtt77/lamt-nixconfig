# this is just a temmporary layout when we migrated from legacy deployment to disko
# using this one agaist a new disko mode will cause:
# Unable to set partition 2's name to 'nixos'!
# OR: mkfs.vfat: unable to open /dev/disk/by-label/boot: No such file or directory

{ inputs, disks ? ["/dev/sda"], ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      boot = {
        type = "disk";
        device = builtins.elemAt disks 0;
        content = {
          type = "gpt";
          partitions = {
            # Boot partition
            ESP = rec {
              start = "1M";
              end = "512M";
              type = "EF00";
              label = "boot";
              device = "/dev/disk/by-label/${label}";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                extraArgs = [ "-n ${label}" ];
              };
            };
            # Root partition ext4
            root = rec {
              # start = "512M";
              # end = "100%";
              size = "100%";
              label = "nixos";
              device = "/dev/disk/by-label/${label}";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                extraArgs = [ "-L ${label}" ];
              };
            };
            # Swap, if enabled, set root.end = "-4G"
            # swap = {
            #   start = "-4G";
            #   size = "4G";
            #   content = {
            #     type = "swap";
            #   };
            # };
          };
        };
      };
    };
  };
}
