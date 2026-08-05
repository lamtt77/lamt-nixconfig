{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  my,
  myargs,
  ...
}:
{
  imports = [
    ./hardware-utils.nix
    (import ../../modules/disko {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  networking =
    my.mkStaticNetworking (
      mydefs.networkingDefaults
      // {
        ip = my.hostAddress myargs.hostname;
        interface = "ens18";
      }
    )
    // {
      extraHosts = ''
        127.0.0.1 cache.lamhub.com
      '';
    };

  virtualisation.docker.enable = true;

  services.qemuGuest.enable = true;

  environment.systemPackages = [
    (pkgs.ovftool.override { acceptBroadcomEula = true; })
  ];

  users.users.deploy.openssh.authorizedKeys.keys = [
    mydefs.nixBuilderPubkey
  ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
