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
    (import ../../modules/disko {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  # The active DHCP server does not currently advertise a resolver. Keep the
  # LAN resolver explicit so the signed local Nix cache remains reachable.
  networking.nameservers = mydefs.networkingDefaults.nameservers;

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
