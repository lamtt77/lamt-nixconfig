{ inputs, disks ? ["/dev/sda"], ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      boot = {
        device = builtins.elemAt disks 0;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
