# nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=./hosts/minimal-iso/default.nix
let
  mydefs = import ../../defines.nix;
in
  {
    modulesPath,
    pkgs,
    ...
  }: {
    imports = [
      "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ];

    # for promox: qm terminal <vmid> serial0
    boot.kernelParams = ["console=ttyS0"];

    boot.kernelPackages = pkgs.linuxPackages_latest;

    nix.settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
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
  }
