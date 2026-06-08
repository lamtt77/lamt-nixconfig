{
  myargs,
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  settingsStr = lib.my.serializeNixSettings { inherit config options; };

  nixConfText = ''
    # Generated declaratively by nix-darwin (modules/os/darwin/autorun/core.nix)
    # Merges base configurations with Darwin-specific overrides.
    ${settingsStr}
    ${config.nix.extraOptions}
  '';
in
{
  nix = {
    # Rely on Determinate to manage nix for us instead of nix-darwin
    enable = false;

    package = pkgs.nix;

    # Darwin-specific overrides that merge with base configurations
    settings = {
      always-allow-substitutes = true;
    };
  };

  environment = {
    pathsToLink = [ "/Applications" ];
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
    primaryUser = "${myargs.username}";

    activationScripts.extraActivation.text = ''
      echo "configuring /etc/nix/nix.custom.conf..."
      mkdir -p /etc/nix
      cp -f ${pkgs.writeText "nix.custom.conf" nixConfText} /etc/nix/nix.custom.conf
    '';

    activationScripts.postActivation.text = ''
      if [ ! -d /var/cache/man ] || [ -z "$(find /var/cache/man -name '*.gz' -mtime -7 2>/dev/null)" ]; then
        mkdir -p /var/cache/man
        ${pkgs.man-db}/bin/mandb
      fi

      # Reload settings from the database to apply them to the current session without logging out
      echo "reloading macOS system settings..."
      sudo -u ${myargs.username} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';
  };
}
