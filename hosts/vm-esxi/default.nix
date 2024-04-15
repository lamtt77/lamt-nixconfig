{ config, lib, ... }: {
  imports = [
    ./hardware-vm-esxi.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  networking.hostName = "esxi-nixos";

  # networking.interfaces.ens192.useDHCP = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.xserver.enable = true;
}
