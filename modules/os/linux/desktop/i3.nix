{ inputs, config, lib, pkgs, username, ... }:

with lib;
let
  inherit (inputs) self;
  cfg = config.modules.os.linux.desktop.i3;
in {
  options.modules.os.linux.desktop.i3 = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    # setup windowing environment
    services.xserver = {
      enable = true;
      dpi = 224;

      xkb.layout = "us";

      desktopManager = {
        xterm.enable = false;
        wallpaper.mode = "fill";
      };

      displayManager = {
        defaultSession = "none+i3";
        lightdm.enable = true;
        # startx.enable = true;

        sessionCommands = ''
        ${pkgs.xorg.xset}/bin/xset r rate 200 40
      '';
      };

      windowManager = {
        i3.enable = true;
        # dwm.enable = true;
      };
    };

    home-manager.users.${username} = {
      xdg.configFile = {
        "i3".source = "${self}/config/_linux/i3";
        "rofi".source = "${self}/config/_linux/rofi";
      };

      home.packages = with pkgs; [ rofi ];

      programs.i3status = {
        enable = true;

        general = {
          colors = true;
          color_good = "#8C9440";
          color_bad = "#A54242";
          color_degraded = "#DE935F";
        };

        modules = {
          ipv6.enable = false;
          "wireless _first_".enable = false;
          "battery all".enable = false;
        };
      };
    };
  };
}
