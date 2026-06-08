mydefs: {
  pve1 = {
    hostname = "pve1";
    proxmoxNode = "pve-dl360p";
    finalIp = mydefs.hosts.pve1.ip;
    netmask = mydefs.networkingDefaults.netmask;
    gateway = mydefs.networkingDefaults.gateway;
    disks = [
      "sda"
      "sdb"
    ];
    diskFilters = [
      {
        key = "ID_MODEL";
        value = "LOGICAL VOLUME";
      }
    ];
    networkTemplate = "interface-production";
    includeClusterStorage = true;
    requiresRefind = false;
  };

  pve2 = {
    hostname = "pve2";
    proxmoxNode = "pve2";
    finalIp = mydefs.hosts.pve2.ip;
    netmask = mydefs.networkingDefaults.netmask;
    gateway = mydefs.networkingDefaults.gateway;
    disks = [ "nvme0n1" ];
    diskFilters = [ ];
    networkTemplate = "interface-production";
    includeClusterStorage = true;
    requiresRefind = true;
  };

  pve-test = {
    hostname = "pve-test";
    proxmoxNode = "pve-test";
    finalIp = "192.168.250.10";
    netmask = "24";
    gateway = "192.168.250.1";
    disks = [ "vda" ];
    diskFilters = [ ];
    autoBoot = true;
    installerNetworkSource = "from-dhcp";
    # set to true for headless debug
    serialConsole = false;
    networkTemplate = "interface-test";
    includeClusterStorage = false;
    requiresRefind = false;
  };
}
