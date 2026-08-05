{
  inputs,
  disks ? if variant == "digitalocean" then [ "/dev/vda" ] else [ "/dev/sda" ],
  ephemeral ? false,
  variant ? "generic",
}:
let
  device = builtins.elemAt disks 0;
  partitions =
    if variant == "digitalocean" then
      {
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
      }
    else
      {
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
            mountpoint = if ephemeral then "/persist" else "/";
          };
        };
      };
in
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      boot = {
        inherit device;
        type = "disk";
        content = {
          type = "gpt";
          inherit partitions;
        };
      };
    };
  };
}
