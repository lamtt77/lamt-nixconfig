{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  ...
}:
{
  imports = [
    ./hardware-avon.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  # networking = {
  #   defaultGateway = mydefs.networking.avon.gateway;
  #   inherit (mydefs.networking.avon) nameservers;
  #   interfaces.ens18 = {
  #     useDHCP = false;
  #     ipv4.addresses = [
  #       {
  #         address = mydefs.networking.avon.ip;
  #         prefixLength = 24;
  #       }
  #     ];
  #   };
  #   # iperf testing port
  #   firewall.allowedTCPPorts = [mydefs.networking.avon.iperfPort];
  #   firewall.allowedUDPPorts = [mydefs.networking.avon.iperfPort];
  # };

  fileSystems."/mnt/VM" = {
    device = mydefs.hosts.avon.nas;
    fsType = "nfs";
  };

  environment.systemPackages = [
    (pkgs.ovftool.override { acceptBroadcomEula = true; })
  ];

  virtualisation.docker.enable = true;
  virtualisation.vmware.guest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
