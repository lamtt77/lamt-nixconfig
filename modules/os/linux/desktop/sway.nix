{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (inputs) self;
  cfg = config.modules.os.linux.desktop.sway;
in {
  options.modules.os.linux.desktop.sway = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    environment.sessionVariables = {
      GTK_USE_PORTAL = "1";
      # GDK_BACKEND = "wayland";
      # WLR_DRM_NO_ATOMIC = "1";
      # WLR_NO_HARDWARE_CURSORS = "1";
    };

    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [xdg-desktop-portal-gtk];
      config.common.default = "*";
    };

    services = {
      greetd = {
        enable = true;
        settings = {
          default_session.command = "${lib.getExe pkgs.greetd.tuigreet} --time --cmd sway";
          # Autologin
          initial_session = {
            command = "sway";
            user = "${config.user}";
          };
        };
      };

      # pipewire = {
      #   enable = true;
      #   alsa.enable = true;
      #   alsa.support32Bit = true;
      #   pulse.enable = true;
      #   jack.enable = true;
      # };
    };

    home-manager.users.${config.user} = {config, ...}: {
      modules.hm.base.polkit.enable = true;

      wayland.windowManager.sway = {
        package = null;
        enable = true;
        xwayland = true;
        systemd.enable = true;

        # extraConfig = ''
        # '';
      };

      xdg.configFile = {
        "sway".source = "${self}/config/_linux/sway";
        # "sway/custom.conf".source = "${mkLink}/config/sway/custom.conf";
      };

      qt = {
        enable = true;
        platformTheme.name = "adwaita";
        style.name = "adwaita";
        style.package = pkgs.adwaita-qt;
      };

      home.packages = with pkgs; [
        swaylock
        swayidle

        xdg-utils # for opening default programs when clicking links
        glib # gsettings
        grim # screenshot functionality
        slurp # screenshot functionality
        wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
        bemenu # wayland clone of dmenu
        mako # notification system developed by swaywm maintainer

        dracula-theme # gtk theme
        adwaita-icon-theme # default gnome cursors

        wdisplays # tool to configure displays
        wlr-randr
        kanshi # autorandr

        libnotify # notify-send
        wev # wayland event view
        wofi

        #   swayr
        #   autotiling-rs
        i3status
      ];
    };
  };
}
