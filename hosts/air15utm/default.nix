{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-air15utm.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = ["/dev/vda"];
    })
  ];

  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  # https://discourse.nixos.org/t/adding-virtio-drivers-to-nixos-configuration/47217/4
  services.spice-vdagentd.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.lxd.enable = true;

  modules.os.base.services.sops.enable = true;
  modules.os.linux.services.openssh.enable = true;

  # modules.os.linux.desktop.i3.enable = true;
  modules.os.linux.desktop.hyprland.enable = true;
  # modules.os.linux.desktop.sway.enable = true;
  # modules.os.linux.desktop.plasma.enable = true;
  # modules.os.linux.desktop.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "xrandr-auto" ''
      xrandr --output Virtual-1 --auto
    '')
  ];
}
