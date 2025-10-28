{
  inputs,
  config,
  lib,
  ...
}: {
  imports = [
    ./hardware-utils.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = ["/dev/sda"];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  modules.os.base.services.tailscale.enable = true;
  modules.os.linux.services.openssh.enable = true;

  virtualisation.docker.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
