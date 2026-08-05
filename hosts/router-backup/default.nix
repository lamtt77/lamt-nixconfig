{
  inputs,
  config,
  mydefs,
  ...
}:
{
  imports = [
    ./hardware-router_backup.nix
    (import ../../modules/disko {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  boot.growPartition = true;
  services.openssh.enable = true;

  sops.secrets."idrac/ip" = {
    owner = "root";
  };
  sops.secrets."idrac/password" = {
    owner = "root";
  };

  modules.os.linux.services.dell-ipmi-fan = {
    idracIpFile = config.sops.secrets."idrac/ip".path;
    passwordFile = config.sops.secrets."idrac/password".path;
  };

  modules.os.linux.services.router = {
    isMaster = false;
    wanIp = "192.168.0.3";
    lanIp = "192.168.1.3";
    syncIp = "192.168.4.3";
    vipLan = "192.168.1.1";
    vipWan = "192.168.0.4";
    hostname = "router-backup";
    enableHA = true;
    priority = 100;
    enablePxe = true;
    pxeTarget = "pve2";
  };

  services.qemuGuest.enable = true;

  networking.firewall.allowedTCPPorts = [ 5201 ]; # iperf3 server port
  networking.firewall.allowedUDPPorts = [ 5201 ]; # iperf3 UDP mode
}
