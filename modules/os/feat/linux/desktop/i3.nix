{
  config,
  pkgs,
  myargs,
  ...
}:
{
  # We need an XDG portal for various applications to work properly,
  # such as Flatpak applications.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  services = {
    displayManager.defaultSession = "none+i3";

    xserver = {
      enable = true;
      xkb.layout = "us";
      dpi = 224;

      desktopManager = {
        xterm.enable = false;
        wallpaper.mode = "fill";
      };

      displayManager = {
        lightdm.enable = true;
        # startx.enable = true;

        # AARCH64: For now, on Apple Silicon, we must manually set the
        # display resolution. This is a known issue with VMware Fusion.
        sessionCommands = ''
          ${pkgs.xset}/bin/xset r rate 200 60
        '';
      };

      windowManager = {
        i3.enable = true;
        # dwm.enable = true;
      };
    };
  };

  home-manager.users.${myargs.username} = {
    xresources.extraConfig = builtins.readFile ../../../../../config/Xresources;

    xdg.configFile = {
      "i3".source = ../../../../../config/_linux/i3;
      "rofi".source = ../../../../../config/_linux/rofi;
    };

    # make cursor not tiny on hidpi screens
    home.pointerCursor = {
      name = "Vanilla-DMZ";
      package = pkgs.vanilla-dmz;
      size = 128;
      x11.enable = true;
    };

    home.packages = with pkgs; [
      rofi
      # xss-lock                # for screen-saver

      feh # image viewer
      dragon-drop # drag'n'drop from the terminal
      xclip
      xdotool
      xwininfo
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
}
