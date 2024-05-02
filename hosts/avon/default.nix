{ inputs, config, lib, ... }: {
  imports = [
    ./hardware-avon.nix
    (import ../_disko/legacy.nix {inherit inputs; disks = ["/dev/sda"];})
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  modules.os.base.services.agenix.enable = true;
  modules.os.linux.services.openssh.enable = true;
  modules.os.linux.services.fail2ban.enable = true;
  modules.os.linux.services.nginx.enable = true;
  modules.os.linux.services.postfix.enable = true;
  modules.os.linux.services.gitea.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
