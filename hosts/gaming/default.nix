{ inputs, config, lib, ... }: {
  imports = [
    ./hardware-gaming.nix
    (import ../_disko/generic.nix {inherit inputs; disks = ["/dev/sda"];})
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  modules.os.linux.services.openssh.enable = true;

  services.minecraft-server.enable = true; # Setup Minecraft server

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
