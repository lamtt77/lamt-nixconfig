{ pkgs, lib, isWSL, ... }:

lib.optionalAttrs (!isWSL) {
  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the systemd-boot EFI boot loader.
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 15;
  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  # boot.loader.systemd-boot.consoleMode = "0";
  # pick the highest resolution for systemd-boot's console.
  boot.loader.systemd-boot.consoleMode = lib.mkDefault "max";

  # this is for disko hybrid mode
  # boot.loader.grub.enable = true;
  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # # must set here and disko will handle later on
  # boot.loader.grub.device = "nodev";

  # # Use the GRUB 2 boot loader.
  # boot.loader.grub.enable = true;
  # boot.loader.grub.device = "/dev/sda";
}
