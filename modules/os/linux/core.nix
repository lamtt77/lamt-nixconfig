{ pkgs, inputs, username, ... }:

let
  inherit (inputs.self) mydefs;
in {
  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  time.timeZone = "Australia/Sydney";

  # NOTE Define a user account. Don't forget to set an initial password with ‘passwd’.
  # OR this will have an empty password (locked-in status, only accept ssh key authorization)
  # users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "docker" "wheel" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = mydefs.ssh-authorizedKeys;
  };

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

  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" ];
  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  # programs.fish.enable = true;
  programs.zsh.enable = true;

  # List packages installed in system profile. To search, run: $ nix search wget
  environment.systemPackages = with pkgs; [
    killall
    niv
    rxvt_unicode
    xclip
    cifs-utils
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = inputs.self.mydefs.stateVersion; # Did you read the comment?
}
