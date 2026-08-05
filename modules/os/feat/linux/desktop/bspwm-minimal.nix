{
  lib,
  pkgs,
  myargs,
  ...
}:
{
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  services = {
    xrdp.defaultWindowManager = lib.mkDefault "bspwm";

    xserver = {
      enable = true;
      xkb.layout = "us";
      windowManager.bspwm.enable = true;
    };
  };

  home-manager.users.${myargs.username} = {
    home.file = {
      ".config/bspwm/bspwmrc" = {
        executable = true;
        text = ''
          #!/usr/bin/env sh
          sxhkd &

          bspc monitor -d 1 2 3 4 5
          bspc config border_width 2
          bspc config window_gap 4
          bspc config split_ratio 0.52
          bspc config borderless_monocle true
          bspc config gapless_monocle true
        '';
      };

      ".config/sxhkd/sxhkdrc".text = ''
        # Launch terminals and the application launcher
        super + Return
          st
        super + shift + Return
          kitty
        super + p
          rofi -show run

        # Close the focused window
        super + {q,w}
          bspc node -c

        # Focus and swap windows by direction
        super + {h,j,k,l}
          bspc node -f {west,south,north,east}
        super + shift + {h,j,k,l}
          bspc node -s {west,south,north,east}

        # Toggle tiled/floating and tiled/monocle layouts
        super + shift + space
          bspc node -t ~floating
        super + space
          bspc desktop -l next

        # Focus a desktop or send the focused window to it
        super + {1-5}
          bspc desktop -f '^{1-5}'
        super + shift + {1-5}
          bspc node -d '^{1-5}'

        # Resize window (smart directional resizing with hjkl or arrows)
        super + alt + {h,Left}
          bspc node -z left -20 0 || bspc node -z right -20 0
        super + alt + {j,Down}
          bspc node -z bottom 0 20 || bspc node -z top 0 20
        super + alt + {k,Up}
          bspc node -z top 0 -20 || bspc node -z bottom 0 -20
        super + alt + {l,Right}
          bspc node -z right 20 0 || bspc node -z left 20 0

        # Restart or exit bspwm
        super + shift + r
          bspc wm -r
        super + shift + e
          bspc quit
      '';
    };

    home.packages = with pkgs; [
      dmenu
      ghostty
      rofi
      st-custom
      sxhkd
      vim
      xclip
      xdotool
      xfce4-terminal
    ];
  };
}
