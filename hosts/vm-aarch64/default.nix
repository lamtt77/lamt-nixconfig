{ inputs, pkgs, lib, username, ... }:

let
  inherit (inputs.self) mydefs;
  hostip = mydefs.hostip;
in {
  imports = [
    ./hardware-vm-aarch64.nix
    ../../modules/_vmware-guest.nix
  ];

  # Setup qemu so we can run x86_64 binaries
  boot.binfmt.emulatedSystems = ["x86_64-linux"];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  # boot.loader.systemd-boot.consoleMode = "0";

  boot.loader.systemd-boot = {
    # we use Git for version control, so we don't need to keep too many generations.
    configurationLimit = lib.mkDefault 10;
    # pick the highest resolution for systemd-boot's console.
    consoleMode = lib.mkDefault "max";
  };


  # Disable the default module and import our override. We have
  # customizations to make this work on aarch64.
  disabledModules = [ "virtualisation/vmware-guest.nix" ];
  # This works through our custom module imported above
  virtualisation.vmware.guest.enable = true;

  virtualisation.docker.enable = true;

  modules.os.base.services.agenix.enable = true;

  hardware.opengl.enable = true;
  modules.os.linux.desktop.i3.enable = true;
  # modules.os.linux.desktop.sway.enable = true;
  # modules.os.linux.desktop.hyprland.enable = true;

  networking.hostName = "air15-nixos";

  # Interface is this on M1
  # networking.interfaces.ens160.useDHCP = true;
  networking.useDHCP = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "xrandr-auto" ''
      xrandr --output Virtual-1 --auto
    '')

    # This is needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this and seeing
    # if the clipboard sill works.
    gtkmm3
  ];

  # Share our host filesystem, host must *enable* sharing option or else see black screen at boot
  # disable vmware hgfs because performance is impacted badly for big directories
  # read: https://codearcana.com/posts/2015/12/04/why-are-builds-on-hgfs-so-slow.html
  #
  # fileSystems."/host" = {
  #   fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
  #   device = ".host:/";
  #   options = [
  #     # comment umask to preserve permission of files from host, vm reboot needed if changes
  #     # "umask=22"
  #     "uid=1000"
  #     "gid=100"
  #     "allow_other"
  #     "auto_unmount"
  #     "defaults"
  #   ];
  # };

  # smb: not-in-used
  # fileSystems."/mnt/share" = {
  #   device = "//${hostip}/${user}";
  #   fsType = "cifs";
  #   options = ["credentials=/etc/nixos/smb-secrets,uid=501,gid=100"];
  # };

  # use nfsd instead of vmware hgfs for much less CPU usage, thus increase 10x performnace for big directories
  # host must turn on nfsd daemon
  fileSystems."/mnt/${username}" = {
    device = "${hostip}:/Users/${username}";
    fsType = "nfs";
    options = [
      "vers=3"
    ];
  };
}
