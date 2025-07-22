{ inputs, config, pkgs, lib, username, ... }:

with lib;
let
  cfg = config.modules.os.linux.desktop.hyprland;

  hypr-run = pkgs.writeShellScriptBin "hypr-run" ''
    export XDG_SESSION_TYPE="wayland"
    export XDG_SESSION_DESKTOP="Hyprland"
    export XDG_CURRENT_DESKTOP="Hyprland"

    systemd-run --user --scope --collect --quiet --unit="hyprland" \
        systemd-cat --identifier="hyprland" ${pkgs.hyprland}/bin/Hyprland $@

    ${pkgs.hyprland}/bin/hyperctl dispatch exit
  '';
in
{
  options.modules.os.linux.desktop.hyprland = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    xdg.portal.enable = true;
    programs.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.system}.hyprland;
      portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
    };

    nix.settings = {
      substituters = ["https://hyprland.cachix.org"];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    programs = {
      dconf.enable = true;
      file-roller.enable = true;
    };

    environment = {
      systemPackages = with pkgs; [
        polkit_gnome
        gnome.nautilus
        gnome.zenity
      ];
    };

    services = {
      xserver = {
        # for X11
        enable = true;

        displayManager.lightdm = {
          enable = false; # greetd instaed
        };
      };

      greetd = {
        enable = true;
        restart = false;
        settings = {
          default_session = {
            command = ''
            ${lib.makeBinPath [pkgs.greetd.tuigreet]}/tuigreet -r --asterisks --time \
              --cmd ${lib.getExe hypr-run}
          '';
          };
        };
      };

      dbus = {
        enable = true;
        # Make the gnome keyring work properly
        packages = [ pkgs.gnome-keyring pkgs.gcr ];
      };

      gnome = {
        gnome-keyring.enable = true;
        sushi.enable = true;
      };

      gvfs.enable = true;
    };

    security = {
      pam = {
        services = {
          # unlock gnome keyring automatically with greetd
          greetd.enableGnomeKeyring = true;
        };
      };
    };

    home-manager.users.${username} = {
      mkLink = config.lib.file.mkOutOfStoreSymlink
        config.home.homeDirectory + "/" + inputs.self.mydefs.myRepoName;
      xdg.configFile."hypr/custom.conf".source = "${mkLink}/config/hypr/custom.conf";

      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
        package = inputs.hyprland.packages.${pkgs.system}.hyprland;

        extraConfig = ''source=./custom.conf'';
      };

      home.packages = with pkgs; [
        # hyprpaper # wallpaper
        hyprpicker
        unstable.hyprlock

        wofi
        grim
        grimblast
        libva-utils
        playerctl
        slurp
        wdisplays
        wf-recorder
        wl-clipboard
        wmctrl

        qalculate-gtk
        udiskie
        dmenu

        mako # notification system developed by swaywm maintainer
        libnotify # notify-send

        glfw-wayland # kitty seems to require this
      ];

      home.sessionVariables = {
        _JAVA_AWT_WM_NONREPARENTING = "1";
        CLUTTER_BACKEND = "wayland";
        GDK_BACKEND = "wayland";
        MOZ_ENABLE_WAYLAND = "1";
        QT_QPA_PLATFORM = "wayland";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        SDL_VIDEODRIVER = "wayland";
        XDG_SESSION_TYPE = "wayland";

        WLR_NO_HARDWARE_CURSORS = 1;
        NIXOS_OZONE_WL = "1";

        # no impact
        # WLR_RENDERER_ALLOW_SOFTWARE = "1";

        # not working
        # WLR_DRM_NO_ATOMIC = 1;
        # WLR_BACKEND = "vulkan";
      };

      services = {
        avizo.enable = true;
        clipman.enable = true;
        wlsunset = {
          enable = true;
          latitude = "51.51";
          longitude = "-2.53";
        };
      };

      qt = {
        enable = true;
        platformTheme.name = "adwaita";
        style.name = "adwaita";
        style.package = pkgs.adwaita-qt;
      };

      systemd.user.services.polkit-gnome-authentication-agent-1 = {
        Unit.Description = "polkit-gnome-authentication-agent-1";
        Install.WantedBy = [ "graphical-session.target" ];
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
      };
    };
  };
}
