{ config, lib, ... }:

with lib;
let cfg = config.modules.os.linux.desktop.gnome;
in {
  options.modules.os.linux.desktop.gnome = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    services.xserver = {
      enable = true;
      xkb.layout = "us";
      desktopManager.gnome.enable = true;
      displayManager.gdm.enable = true;
    };
  };
}
