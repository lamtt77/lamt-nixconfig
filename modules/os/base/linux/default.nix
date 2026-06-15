{ ... }:
{
  imports = [
    ./_ozone.nix
    ./boot.nix
    ./core.nix
    ./dbus.nix
    ./earlyoom.nix
    ./gtk.nix
    ./networking.nix
    ./persist.nix
    ./systemd.nix
    ./zramswap.nix
  ];
}
