{
  lib,
  pkgs,
  myargs,
  ...
}:
let
  hypr-run = pkgs.writeShellScriptBin "hypr-run" ''
    systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY \
      XDG_CURRENT_DESKTOP \
      HYPRLAND_INSTANCE_SIGNATURE

    systemd-run --user --scope --collect --quiet --unit="hyprland" \
        systemd-cat --identifier="hyprland" ${pkgs.hyprland}/bin/Hyprland $@

    ${pkgs.hyprland}/bin/hyperctl dispatch exit
  '';
in
{
  xdg.portal.enable = true;

  # Hyprland's aquamarine requires newer MESA drivers.
  # hardware.graphics = {
  #   package = pkgs.unstable.mesa;
  #   package32 = pkgs.unstable.pkgsi686Linux.mesa;
  # };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;

    # package = inputs.hyprland.packages.${final.system}.hyprland;
    # portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  environment = {
    systemPackages = with pkgs; [
      # Hyprland's default
      wofi

      hyprlock # *fast* lock screen
      hyprpicker # screen-space color picker
      hyprshade # to apply shaders to the screen
      hyprshot # instead of grim(shot) or maim/slurp

      ## For Hyprland
      mako # dunst for wayland
      swaybg # feh (as a wallpaper manager)
      xorg.xrandr # for XWayland windows

      ## For CLIs
      gromit-mpx # for drawing on the screen
      pamixer # for volume control
      wlr-randr # for monitors that hyprctl can't handle
      ## Waiting for NixOS/nixpkgs@7249e6c56141 to reach nixos-unstable
      # wf-recorder    # for screencasting
    ];
  };

  services = {
    greetd = {
      enable = true;
      restart = false;
      settings = {
        default_session = {
          command = ''
            ${lib.makeBinPath [ pkgs.tuigreet ]}/tuigreet -r --asterisks --time \
              --cmd ${lib.getExe hypr-run}
          '';
        };
      };
    };

    # required for screensharing
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
  };

  security.pam.services = {
    # unlock gnome keyring automatically with greetd
    greetd.enableGnomeKeyring = true;
  };

  home-manager.users.${myargs.username} =
    {
      inputs,
      config,
      my,
      ...
    }:
    let
      mkLink = my.mkLinkCfg config;
    in
    {
      xdg.configFile."hypr/custom.conf".source = mkLink "config/hypr/custom.conf";

      wayland.windowManager.hyprland = {
        enable = true;
        # set the Hyprland and XDPH packages to null to use the ones from the NixOS module
        package = null;
        portalPackage = null;
        # default on air15vm: monitor=Virtual-1,3420x1946,0x0,2
        # or lower resolution: monitor=Virtual-1,1710x973,0x0,1
        extraConfig = "source=./custom.conf";
      };

      home.packages = with pkgs; [
        # Program     Substitutes for
        ripdrag # dragon-drop
        wev # xev
        wl-clipboard # xclip
        wtype # xdotool (sorta)
        swappy # swappy/Snappy/sharex
        slurp # slop
        swayimg # feh (as an image previewer)
        imv
      ];

      home.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        ELECTRON_OZONE_PLATFORM_HINT = "auto";

        # we are running under Vmware Fusion, uncomment if having issue
        # LIBGL_ALWAYS_SOFTWARE = "1";
        # or:
        # WLR_RENDERER_ALLOW_SOFTWARE = "1";

        # # not really needed, for now
        # XDG_SESSION_TYPE = "wayland";
        # MOZ_ENABLE_WAYLAND = "1";
        # WLR_NO_HARDWARE_CURSORS = 1;
        # _JAVA_AWT_WM_NONREPARENTING = "1";
        # CLUTTER_BACKEND = "wayland";
        # GDK_BACKEND = "wayland";
        # QT_QPA_PLATFORM = "wayland";
        # QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        # SDL_VIDEODRIVER = "wayland";
        # LIBSEAT_BACKEND = "logind";
      };

      services = {
        clipman.enable = true;
      };

      qt = {
        enable = true;
        platformTheme.name = "adwaita";
        style.name = "adwaita";
        style.package = pkgs.adwaita-qt;
      };
    };
}
