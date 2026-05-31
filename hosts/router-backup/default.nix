{
  inputs,
  config,
  mydefs,
  ...
}: {
  imports = [
    ./hardware-router_backup.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = ["/dev/sda"];
    })
  ];

  deployment = {
    targetIp = config.modules.os.linux.services.router.lanIp;
    vmid = "107";
    proxmox = {
      host = mydefs.hosts.pve2.ip;
      bios = "ovmf";
      diskBus = "scsi";
    };
  };

  boot.growPartition = true;
  services.openssh.enable = true;
  modules.os.base.services.sops.enable = true;

  sops.secrets."idrac/ip" = {
    owner = "root";
  };
  sops.secrets."idrac/password" = {
    owner = "root";
  };

  modules.os.linux.services.dell-ipmi-fan = {
    enable = true;
    idracIpFile = config.sops.secrets."idrac/ip".path;
    passwordFile = config.sops.secrets."idrac/password".path;
  };

  modules.os.linux.services.router = {
    enable = true;
    isMaster = false;
    wanIp = "192.168.0.3";
    lanIp = "192.168.1.3";
    syncIp = "192.168.4.3";
    vipLan = "192.168.1.1";
    vipWan = "192.168.0.4";
    hostname = "router-backup";
    enableHA = true;
    priority = 100;
    enablePxe = false;
  };

  services.qemuGuest.enable = true;

  networking.firewall.allowedTCPPorts = [ 5201 ];  # iperf3 server port
  networking.firewall.allowedUDPPorts = [ 5201 ];  # iperf3 UDP mode
}
