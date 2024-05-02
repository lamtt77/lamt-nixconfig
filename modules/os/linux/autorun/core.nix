{ inputs, pkgs, username, ... }:

{
  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  i18n.defaultLocale = "en_US.UTF-8";

  security = {
    sudo.wheelNeedsPassword = false;
    polkit.enable = true;
    rtkit.enable = true;
  };

  # Create dirs for home-manager
  systemd.tmpfiles.rules = [
    "d /nix/var/nix/profiles/per-user/${username} 0755 ${username} root"
  ];

  services = {
    chrony.enable = true;
    journald.extraConfig = "SystemMaxUse=250M";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = inputs.self.mydefs.stateVersion; # Did you read the comment?
}
