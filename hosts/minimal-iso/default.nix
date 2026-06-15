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
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  config = {
    # for promox: qm terminal <vmid> serial0
    # console=ttyS0 is for x86 serial, can cause kernel panic on aarch64
    boot.kernelParams = (lib.optionals pkgs.stdenv.hostPlatform.isx86 [ "console=ttyS0" ]) ++ [
      "net.ifnames=0"
    ];
    boot.kernelPackages = pkgs.linuxPackages_latest;

    services.qemuGuest.enable = true;
    virtualisation.vmware.guest.enable = true;

    nix.settings = {
      experimental-features = "nix-command flakes";
      substituters = [
        "https://cache.lamhub.com?priority=10"
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "cache.lamhub.com-1:D/ywCfChYM7EGJ3UbQsH2YX8Svq2okabE+qdalC4fdw="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
      connect-timeout = 3;
      stalled-download-timeout = 10;
    };

    environment.systemPackages = with pkgs; [
      nixVersions.latest
      gitMinimal
      jq
      rsync
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
      openssh.authorizedKeys.keys = [ mydefs.mySshAuthKey ];
    };
  };
}
