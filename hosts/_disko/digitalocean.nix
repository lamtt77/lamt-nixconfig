{
  inputs,
  disks ? ["/dev/vda"],
  ...
}: {
  imports = [inputs.disko.nixosModules.disko];

  disko.devices = {
    disk = {
      boot = {
        device = builtins.elemAt disks 0;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            reserved = {
              size = "4M";
              type = "EF02";
            };
            boot = {
              size = "1023M";
              content = {
                type = "filesystem";
                format = "ext4";
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
