{
  inputs,
  config,
  lib,
  my,
  mydefs,
  myargs,
  ...
}:
{
  imports = [
    ./hardware-fcmbuilder.nix
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

  networking =
    my.mkStaticNetworking {
      ip = my.hostAddress myargs.hostname;
      interface = "eth0";
      gateway = "192.168.7.1";
      nameservers = [
        "192.168.7.2"
        "192.168.7.4"
      ];
    }
    // {
      useDHCP = false;
    };

  # The initial platform is VMware ESXi. QEMU guest support is retained for a
  # later Proxmox migration without changing the guest configuration.
  virtualisation.vmware.guest.enable = true;
  services.qemuGuest.enable = true;

  users.users.deploy.openssh.authorizedKeys.keys = [ mydefs.mySshAuthKey ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
