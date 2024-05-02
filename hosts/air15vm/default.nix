{ inputs, pkgs, username, ... }:

let
  inherit (inputs.self) mydefs;
  hostURL = mydefs.hostURL;
in {
  imports = [
    ./hardware-air15vm.nix
    (import ../_disko/generic.nix {inherit inputs; disks = ["/dev/sda"];})
    ../../modules/_vmware-guest.nix
  ];

  # Setup qemu so we can run x86_64 binaries
  boot.binfmt.emulatedSystems = ["x86_64-linux"];
  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  # Disable the default module and import our override. We have
  # customizations to make this work on aarch64.
  disabledModules = [ "virtualisation/vmware-guest.nix" ];
  # This works through our custom module imported above
  virtualisation.vmware.guest.enable = true;

  virtualisation.docker.enable = true;

  modules.os.base.services.agenix.enable = true;
  modules.os.linux.services.openssh.enable = true;

  hardware.opengl.enable = true;
  modules.os.linux.desktop.i3.enable = true;
  # modules.os.linux.desktop.sway.enable = true;
  # modules.os.linux.desktop.hyprland.enable = true;

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

  # # smb share
  # fileSystems."/mnt/${username}" = let
  #   credentials = config.age.secrets."${hostname}_smb-secrets".path;
  # in {
  #   device = "//${hostURL}/${username}";
  #   fsType = "cifs";
  #   # https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html
  #   options = [
  #     "nofail,_netdev"
  #     # "uid=1000,gid=100,dir_mode=0755,file_mode=0755"
  #     "uid=1000,gid=100"
  #     "vers=3.0,credentials=${credentials}"
  #   ];
  # };

  # use nfsd instead of vmware hgfs for much less CPU usage, thus increase 10x performnace for big directories
  # host must turn on nfsd daemon
  fileSystems."/mnt/${username}" = {
    device = "${hostURL}:/Users/${username}/lab";
    fsType = "nfs";
    options = [
      "vers=3"
    ];
  };
}
