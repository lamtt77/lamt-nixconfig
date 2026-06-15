{
  inputs,
  config,
  pkgs,
  mydefs,
  ...
}:
let
  hostURL = mydefs.hostURL;
in
{
  imports = [
    ./hardware-air15vm.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # Setup qemu so we can run x86_64 binaries
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  virtualisation.vmware.guest.enable = true;

  # Virtualization settings
  virtualisation.docker.enable = true;

  # Tell the DHCP client to ignore the VMware DNS proxy (172.16.138.2)
  # and use your local router directly.
  networking.dhcpcd.extraConfig = ''
    static domain_name_servers=192.168.1.1
  '';

  # modules.os.linux.services.kdeconnect.enable = true;

  # modules.os.linux.desktop.i3.enable = true;
  # modules.os.linux.desktop.hyprland.enable = true;
  # modules.os.linux.desktop.sway.enable = true;
  # modules.os.linux.desktop.plasma.enable = true;
  # modules.os.linux.desktop.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "xrandr-auto" ''
      xrandr --output Virtual-1 --auto
    '')

    # This may be needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this -> still work!
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
  # fileSystems."/mnt/${config.user}" = let
  #   credentials = config.sops.secrets."${hostname}/smb-secrets".path;
  # in {
  #   device = "//${hostURL}/${config.user}";
  #   fsType = "cifs";
  #   # https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html
  #   options = [
  #     "nofail,_netdev"
  #     # "uid=1000,gid=100,dir_mode=0755,file_mode=0755"
  #     "uid=1000,gid=100"
  #     "vers=3.0,credentials=${credentials}"
  #   ];
  # };

  # # use nfsd instead of vmware hgfs for much less CPU usage, thus increase 10x performnace for big directories
  # # host must turn on nfsd daemon
  # fileSystems."/mnt/${config.user}" = {
  #   device = "${hostURL}:/Users/${config.user}/lab";
  #   fsType = "nfs";
  #   options = [ "vers=3" ];
  #   # for non-apple nfs
  #   # options = [ "nfsvers=4.2" "x-systemd.automount" "noauto" ];
  # };
}
