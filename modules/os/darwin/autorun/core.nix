{
  config,
  pkgs,
  ...
}: {
  # rely on Determinate to manage nix for us instead of nix-darwin
  nix.enable = false;

  # Store management, currently, only nix-darwin supports interval attrs
  # nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 15d";

  nix.gc.interval.Hour = 3;
  nix.optimise.interval.Hour = 4;

  environment = {
    pathsToLink = ["/Applications"];
  };

  # zsh is the default shell on Mac and we want to make sure that we're
  # configuring the rc correctly with nix-darwin paths.
  programs.zsh.enable = true;
  programs.zsh.shellInit = ''
    # Homebrew
    if [ -d '/opt/homebrew' ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    # Nix
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
      . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi
    # End Nix
  '';

  system = {
    stateVersion = 6;
    primaryUser = "${config.user}";

    # activationScripts are executed every time you boot the system or run `nixos-rebuild` / `darwin-rebuild`.
    # activationScripts.postUserActivation.text = ''
    #   # activateSettings -u will reload the settings from the database and apply them to the current session,
    #   # so we do not need to logout and login again to make the changes take effect.
    #   /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    # '';
  };
}
