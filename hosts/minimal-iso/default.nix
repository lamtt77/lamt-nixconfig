# nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=./hosts/minimal-iso/default.nix
let
  mydefs = import ../../defines.nix;
in
  {
    modulesPath,
    pkgs,
    lib,
    config,
    ...
  }: {
    imports = [
      "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ];

    options.iso.vlan.enable = lib.mkEnableOption "VLAN support in ISO";

    config = {
      # for promox: qm terminal <vmid> serial0
      # console=ttyS0 is for x86 serial, can cause kernel panic on aarch64
      boot.kernelParams = (lib.optionals pkgs.stdenv.hostPlatform.isx86 ["console=ttyS0"]) ++ ["net.ifnames=0"];
      boot.kernelPackages = pkgs.linuxPackages_latest;

      services.qemuGuest.enable = true;
      virtualisation.vmware.guest.enable = true;

      nix.settings = {
        experimental-features = "nix-command flakes";
      };

      environment.systemPackages = with pkgs; [
        nixVersions.latest
        git
        jq
        rsync
        vim
        zsh
      ];

      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = true;
        knownHosts = {
          "github.com".publicKey = mydefs.githubPubkey;
          "tea.lamhub.com".publicKey = mydefs.teaPubkey;
        };
      };

      programs.ssh.startAgent = true;

      users.users.root = {
        openssh.authorizedKeys.keys = [mydefs.mySshAuthKey];
      };

      # VLAN config for routers (matches legacy pfSense vmbr0/vmbr1 with VLAN 10 and 40)
      networking.vlans = lib.mkIf config.iso.vlan.enable {
        "eth1.10" = {
          id = 10;
          interface = "eth1";
        };
      };
      networking.interfaces = lib.mkIf config.iso.vlan.enable {
        "eth1.10".useDHCP = true;
      };
    };
  }
