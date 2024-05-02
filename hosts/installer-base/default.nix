{ inputs, pkgs, ...}: let
  inherit (inputs.self) mydefs;
in {
  imports = [
    (import ../../hosts/_disko/generic.nix {inherit inputs; disks = ["/dev/sda"];})
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "0";

  environment.systemPackages = with pkgs; [
    rsync
    gitMinimal
    vim
  ];

  nix.settings = {
    experimental-features = "nix-command flakes";
    auto-optimise-store = true;
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    knownHosts = {
      "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      "tea.lamhub.com".publicKey = mydefs.teaPublicKey;
    };
  };

  programs.ssh.startAgent = true;

  users.users.root = {
    openssh.authorizedKeys.keys = [ "${mydefs.mySshAuthKey}" ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = inputs.self.mydefs.stateVersion; # Did you read the comment?
}
