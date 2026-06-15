{ config, lib, ... }:
{
  programs.kdeconnect = {
    enable = true;
    # GSConnect for gnome
    # package = pkgs.gnomeExtensions.gsconnect;
  };
}
