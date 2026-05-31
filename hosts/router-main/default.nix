{
  inputs,
  config,
  mydefs,
  ...
}: {
  imports = [
    ./hardware-router_main.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = ["/dev/sda"];
    })
  ];

  deployment = {
    targetIp = config.modules.os.linux.services.router.lanIp;
    vmid = "105";
    proxmox = {
      host = mydefs.hosts.pve1.ip;
      bios = "ovmf";
      diskBus = "scsi";
    };
  };

  boot.growPartition = true;
  services.openssh.enable = true;
  modules.os.base.services.sops.enable = true;

  modules.os.linux.services.router = {
    enable = true;
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
  };

  services.qemuGuest.enable = true;

  networking.firewall.allowedTCPPorts = [ 5201 ];  # iperf3 server port
  networking.firewall.allowedUDPPorts = [ 5201 ];  # iperf3 UDP mode
}
