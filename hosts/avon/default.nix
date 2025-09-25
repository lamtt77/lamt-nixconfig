{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  ...
}: {
  imports = [
    ./hardware-avon.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = ["/dev/sda"];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  networking = {
    defaultGateway = mydefs.networking.avon.gateway;
    nameservers = mydefs.networking.avon.nameservers;
    interfaces.ens192 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = mydefs.networking.avon.ip;
          prefixLength = 24;
        }
      ];
    };
    # iperf testing port
    firewall.allowedTCPPorts = [mydefs.networking.avon.iperfPort];
    firewall.allowedUDPPorts = [mydefs.networking.avon.iperfPort];
  };

  fileSystems."/mnt/VM" = {
    device = mydefs.hosts.avon.nas;
    fsType = "nfs";
  };

  environment.systemPackages = with pkgs; [
    ovftool
  ];

  modules.os.base.services.sops.enable = true;
  modules.os.linux.services.openssh.enable = true;
  modules.os.linux.services.fail2ban.enable = true;
  modules.os.linux.services.nginx.enable = true;
  modules.os.linux.services.postfix.enable = true;
  modules.os.linux.services.gitea.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
