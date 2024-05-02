{ config, lib, ... }: {
  imports = [
    ./hardware-vm-esxi.nix
  ];

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.xserver.enable = true;
}
