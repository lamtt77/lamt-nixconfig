{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-router_recovery.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  boot.growPartition = true;
  services.openssh.enable = true;
  modules.os.base.services.sops.enable = true;

  modules.os.linux.services.router = {
    enable = true;
    isMaster = false;
    wanIp = "192.168.0.20";
    lanIp = "192.168.1.20";
    syncIp = "192.168.4.20";
    vipLan = "192.168.1.1";
    vipWan = "192.168.0.4";
    hostname = "router-recovery";
    enableHA = false;
    enableDhcp = false;
    extraInternalInterfaces = [ "eth2" ];
    priority = 50;
    enablePxe = false; # We configure pve-pxe custom-bound to eth2 below
    enableDyndns = false;
  };

  # Custom interface eth2 bound to isolated vmbrPxe bridge
  networking.interfaces.eth2 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.250.1";
        prefixLength = 24;
      }
    ];
  };

  # Firewall rules for isolated PXE network interface
  networking.firewall.interfaces.eth2 = {
    allowedTCPPorts = [ 80 ];
    allowedUDPPorts = [
      67
      68
      69
    ];
  };

  # PXE service running on isolated bridge
  modules.os.linux.services.pve-pxe = {
    enable = true;
    assets = pkgs.pve-pxe-assets.mkPvePxeAssets {
      target = "pve-test";
      bootstrapIp = "192.168.250.1";
    };
    interface = "eth2";
    listenAddress = "192.168.250.1";
    dhcpBackend = "dnsmasq";
  };

  services.qemuGuest.enable = true;

  networking.firewall.allowedTCPPorts = [ 5201 ]; # iperf3 server port
  networking.firewall.allowedUDPPorts = [ 5201 ]; # iperf3 UDP mode
}
