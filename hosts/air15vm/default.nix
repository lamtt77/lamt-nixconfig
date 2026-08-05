{
  inputs,
  config,
  lib,
  myargs,
  pkgs,
  mydefs,
  ...
}:
let
  hostURL = mydefs.hostURL;
in
{
  imports = [
    ./hardware-air15vm.nix
    (import ../../modules/disko {
      inherit inputs;
      disks = [ "/dev/sda" ];
    })
  ];

  # Setup qemu so we can run x86_64 binaries
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
  # after resize the disk, it will grow partition automatically.
  boot.growPartition = true;

  virtualisation.vmware.guest.enable = true;

  # Virtualization settings
  virtualisation.docker.enable = true;

  services = {
    displayManager.defaultSession = "none+bspwm";

    xserver = {
      dpi = 224;

      desktopManager = {
        xterm.enable = false;
        wallpaper.mode = "fill";
      };

      displayManager = {
        lightdm.enable = true;
        sessionCommands = ''
          ${pkgs.xset}/bin/xset r rate 200 60
        '';
      };
    };
  };

  # Tell the DHCP client to ignore the VMware DNS proxy (172.16.138.2)
  # and use your local router directly.
  networking.dhcpcd.extraConfig = ''
    static domain_name_servers=192.168.1.1
  '';

  # modules.os.linux.services.kdeconnect.enable = true;

  # modules.os.linux.desktop.hyprland.enable = true;
  # modules.os.linux.desktop.sway.enable = true;
  # modules.os.linux.desktop.plasma.enable = true;
  # modules.os.linux.desktop.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    # This may be needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this -> still work!
    gtkmm3
  ];

  home-manager.users.${myargs.username} = {
    xdg.configFile."rofi".source = ../../config/_linux/rofi;

    home.pointerCursor = {
      name = "Vanilla-DMZ";
      package = pkgs.vanilla-dmz;
      size = 128;
      x11.enable = true;
    };

    home.file = {
      ".config/bspwm/bspwmrc".text = lib.mkForce ''
        #!/usr/bin/env sh
        sxhkd &

        # VMware Fusion can expose Virtual-1 after the X session starts.
        for _ in 1 2 3 4 5; do
          xrandr --output Virtual-1 --auto && break
          sleep 1
        done

        bspc monitor -d 1 2 3 4 5
        bspc config border_width 2
        bspc config window_gap 4
        bspc config split_ratio 0.52
        bspc config borderless_monocle true
        bspc config gapless_monocle true

        polybar-msg cmd quit >/dev/null 2>&1 || true
        polybar main &
      '';

      ".config/sxhkd/sxhkdrc".text = lib.mkForce ''
        super + Return
          ghostty
        super + shift + Return
          kitty
        super + p
          rofi -show run

        super + {q,w}
          bspc node -c
        super + {h,j,k,l}
          bspc node -f {west,south,north,east}
        super + shift + {h,j,k,l}
          bspc node -s {west,south,north,east}

        super + shift + f
          bspc node -t ~fullscreen
        super + shift + space
          bspc node -t ~floating
        super + space
          bspc desktop -l next

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

        super + shift + r
          bspc wm -r
        super + shift + e
          bspc quit
      '';

      ".config/polybar/config.ini".text = ''
        [bar/main]
        width = 100%
        height = 30
        bottom = true
        dpi = 224
        background = #282a36
        foreground = #f8f8f2
        font-0 = Fira Code:size=10;2
        modules-left = bspwm
        modules-right = filesystem load memory ethernet date
        separator = "  "
        module-margin = 1

        [module/bspwm]
        type = internal/bspwm
        label-focused = %name%
        label-focused-background = #6272a4
        label-focused-padding = 2
        label-occupied = %name%
        label-occupied-padding = 2
        label-empty = %name%
        label-empty-foreground = #6272a4
        label-empty-padding = 2

        [module/filesystem]
        type = internal/fs
        interval = 25
        mount-0 = /
        label-mounted = FS %percentage_used%%

        [module/load]
        type = custom/script
        interval = 5
        exec = ${pkgs.gawk}/bin/awk '{print "LOAD " $1}' /proc/loadavg

        [module/memory]
        type = internal/memory
        interval = 5
        label = MEM %percentage_used%%

        [module/ethernet]
        type = internal/network
        interface-type = wired
        interval = 5
        format-connected = <label-connected>
        format-disconnected = <label-disconnected>
        label-connected = %ifname% %local_ip%
        label-disconnected = ETH down

        [module/date]
        type = internal/date
        interval = 5
        date = %Y-%m-%d %H:%M:%S
        label = %date%
      '';
    };

    home.packages = with pkgs; [
      dragon-drop
      feh
      polybar
      rofi
      xclip
      xdotool
      xwininfo
    ];
  };

  # Share our host filesystem, host must *enable* sharing option or else see black screen at boot
  # disable vmware hgfs because performance is impacted badly for big directories
  # read: https://codearcana.com/posts/2015/12/04/why-are-builds-on-hgfs-so-slow.html
  #
  # fileSystems."/host" = {
  #   fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
  #   device = ".host:/";
  #   options = [
  #     # comment umask to preserve permission of files from host, vm reboot needed if changes
  #     # "umask=22"
  #     "uid=1000"
  #     "gid=100"
  #     "allow_other"
  #     "auto_unmount"
  #     "defaults"
  #   ];
  # };

  # # use nfsd instead of vmware hgfs for much less CPU usage, thus increase 10x performnace for big directories
  # # host must turn on nfsd daemon
  # fileSystems."/mnt/${config.user}" = {
  #   device = "${hostURL}:/Users/${config.user}/lab";
  #   fsType = "nfs";
  #   options = [ "vers=3" ];
  #   # for non-apple nfs
  #   # options = [ "nfsvers=4.2" "x-systemd.automount" "noauto" ];
  # };
}
