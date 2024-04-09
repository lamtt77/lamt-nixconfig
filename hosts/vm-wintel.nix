{ config, lib, ... }: {
  imports = [
    ./hardware/vm-wintel.nix
  ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  networking.hostName = "dell-nixos-wintel";

  # networking.interfaces.ens192.useDHCP = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.xserver.enable = true;
}
