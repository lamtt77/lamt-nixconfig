{
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./hardware-vm-esxi.nix
    (import ../../modules/disko {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.xserver.enable = true;
}
