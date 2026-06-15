let
  mydefs = import ../../defines.nix;
in
{ lib, pkgs, ... }:
{
  wsl = {
    enable = true;
    defaultUser = "nixos";
    startMenuLaunchers = false;
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://cache.lamhub.com?priority=10"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [
      "cache.lamhub.com-1:D/ywCfChYM7EGJ3UbQsH2YX8Svq2okabE+qdalC4fdw="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };
  nix.channel.enable = false;
  nix.nixPath = lib.mkForce [ ];
  nix.registry = lib.mkForce { };

  documentation = {
    enable = false;
    doc.enable = false;
    info.enable = false;
    man.enable = false;
    nixos.enable = false;
  };
  environment.defaultPackages = lib.mkForce [ ];
  programs.command-not-found.enable = false;

  environment.systemPackages = with pkgs; [
    gitMinimal
    jq
    rsync
  ];

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  security.sudo.wheelNeedsPassword = false;
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ mydefs.mySshAuthKey ];
  };

  system.stateVersion = mydefs.stateVersion;
}
