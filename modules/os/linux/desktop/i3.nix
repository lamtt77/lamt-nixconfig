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
    # We need an XDG portal for various applications to work properly,
    # such as Flatpak applications.
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = "*";
    };

    services.xserver = {
      enable = true;
      xkb.layout = "us";
      dpi = 224;

      desktopManager = {
        xterm.enable = false;
        wallpaper.mode = "fill";
      };

      displayManager = {
        defaultSession = "none+i3";
        lightdm.enable = true;
        # startx.enable = true;

        # AARCH64: For now, on Apple Silicon, we must manually set the
        # display resolution. This is a known issue with VMware Fusion.
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

      home.packages = with pkgs; [
        rofi
        # xss-lock                # for screen-saver
      ];

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
