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
    inherit (mydefs.networking.avon) nameservers;
    interfaces.ens18 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = mydefs.networking.avon.ip;
          prefixLength = 24;
        }
      ];
    };
    extraHosts = "127.0.0.1 ts.lamhub.com";
    # iperf testing port
    firewall.allowedTCPPorts = [mydefs.networking.avon.iperfPort];
    firewall.allowedUDPPorts = [mydefs.networking.avon.iperfPort];
  };

  fileSystems."/mnt/VM" = {
    device = mydefs.hosts.avon.nas;
    fsType = "nfs";
  };

  environment.systemPackages = [
    (pkgs.ovftool.override {acceptBroadcomEula = true;})
    pkgs.cloudflared
  ];

  modules.os = {
    base.services.sops.enable = true;
    linux.services = {
      openssh.enable = true;
      fail2ban.enable = true;
      nginx.enable = true;
      postfix.enable = true;
      gitea.enable = true;
      headscale.enable = true;
      gitea-runner.enable = true;
    };
  };

  services.arthur-backup.enable = true;

  virtualisation.docker.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
