{
  inputs,
  config,
  lib,
  mydefs,
  ...
}:
{
  imports = [
    ./hardware-gaming.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  services.minecraft-server.enable = true; # Setup Minecraft server
  services.minecraft-server.eula = true;

  assertions = [
    {
      assertion = config.services.minecraft-server.declarative;
      message = "gaming requires the custom declarative Minecraft feature";
    }
    {
      assertion = builtins.elem 49732 config.networking.firewall.allowedTCPPorts;
      message = "gaming requires the Minecraft socket activation firewall port";
    }
  ];

  virtualisation.docker.enable = true;

  services.qemuGuest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
