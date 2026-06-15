{
  inputs,
  config,
  mydefs,
  ...
}:
{
  imports = [
    ./hardware-router_main.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  boot.growPartition = true;
  services.openssh.enable = true;

  modules.os.linux.services.router = {
    isMaster = true;
    wanIp = "192.168.0.2";
    lanIp = "192.168.1.2";
    syncIp = "192.168.4.2";
    vipLan = "192.168.1.1";
    vipWan = "192.168.0.4";
    hostname = "router-main";
    enableHA = true;
    priority = 150;
    enablePxe = true;
    pxeTarget = "pve1";
  };

  services.qemuGuest.enable = true;

  networking.firewall.allowedTCPPorts = [ 5201 ]; # iperf3 server port
  networking.firewall.allowedUDPPorts = [ 5201 ]; # iperf3 UDP mode
}
