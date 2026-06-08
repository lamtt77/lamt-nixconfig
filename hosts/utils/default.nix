{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  my,
  ...
}:
{
  imports = [
    ./hardware-utils.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  networking = my.mkStaticNetworking (
    mydefs.networkingDefaults
    // {
      ip = config.deployment.targetIp;
      interface = "ens18";
    }
  );

  modules.os.base.services.sops.enable = true;
  sops.secrets.tailscale_preauth_key = { };

  modules.os.base.services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale_preauth_key.path;
  };
  modules.os.linux.services.openssh.enable = true;

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
