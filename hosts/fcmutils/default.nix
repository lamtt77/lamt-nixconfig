{
  inputs,
  config,
  lib,
  my,
  mydefs,
  myargs,
  pkgs,
  ...
}:
let
  # Management IP is authored only in infra/site.nix site.hosts; empty means DHCP.
  targetIp = my.hostAddressOr myargs.hostname "";
in
{
  imports = [
    ./hardware-fcmutils.nix
    (import ../../modules/disko {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  boot = {
    growPartition = true;
    kernelParams = [
      "net.ifnames=0"
      "biosdevname=0"
    ];
  };

  # Dynamic networking: use static IP when infra declares one, otherwise DHCP for local VM testing.
  networking =
    if targetIp != "" then
      my.mkStaticNetworking {
        ip = targetIp;
        interface = "eth0";
        gateway = "192.168.7.1";
        nameservers = [
          "192.168.7.2"
          "192.168.7.4"
        ];
      }
      // {
        useDHCP = false;
      }
    else
      {
        useDHCP = true;
        nameservers = [ "192.168.1.1" ];
      };

  # Support VMware ESXi and Proxmox/QEMU guest drivers/services.
  virtualisation.vmware.guest.enable = true;
  services.qemuGuest.enable = true;

  # Disable ZRAM swap to prevent guest RAM from being used as compressed swap,
  # allowing ESXi memory ballooning to reclaim actual memory when needed.
  zramSwap.enable = lib.mkForce false;

  # Enable a physical swap file on the disk (automatically created by NixOS on ext4)
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4 * 1024; # 4 GB
    }
  ];

  # Adjust kernel sysctl parameters to encourage directory/inode cache reclamation
  # and set standard swappiness for physical swap.
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 150;
  };

  users.users.nixos.openssh.authorizedKeys.keys = [ mydefs.mySshAuthKey ];
  users.users.nixos.packages = with pkgs; [
    bind # dig, host, nslookup
    ipmiview
    ipmitool
    freeipmi
    steam-run
    firefox
  ];

  home-manager.users.nixos = {
    home.sessionVariables = {
      EDITOR = lib.mkForce "vim";
    };
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
