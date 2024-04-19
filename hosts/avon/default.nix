
{ config, lib, ... }: {
  imports = [
    ./hardware-avon.nix
  ];

  modules.os.base.services.agenix.enable = true;

  modules.os.linux.services.openssh.enable = true;
  modules.os.linux.services.fail2ban.enable = true;
  modules.os.linux.services.nginx.enable = true;
  modules.os.linux.services.gitea.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
