{
  inputs,
  config,
  lib,
  mydefs,
  ...
}: {
  imports = [
    ./hardware-gaming.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = ["/dev/sda"];
    })
  ];

  deployment = {
    vmid = "110";
    proxmox = {
      host = mydefs.hosts.pve1.ip;
      bios = "ovmf";
      diskBus = "scsi";
    };
  };

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  modules.os.base.services.tailscale.enable = true;
  modules.os.linux.services.openssh.enable = true;

  services.minecraft-server.enable = true; # Setup Minecraft server

  virtualisation.docker.enable = true;

  services.qemuGuest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
