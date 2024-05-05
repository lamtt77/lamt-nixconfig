{ pkgs, ... }:

{
  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # Add ability to used TouchID for sudo authentication
  security.pam.enableSudoTouchIdAuth = true;

  # this may requires nix-channel
  programs.nix-index.enable = true;

  # Store management, currently, only nix-darwin supports interval attrs
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 15d";
  #
  nix.gc.interval.Hour = 3;
  nix.optimise.interval.Hour = 4;

  environment = {
    extraInit = ''
      # install homebrew if not found
      if [ ! -f "/opt/homebrew/bin/brew" ]; then
         ${pkgs.bash}/bin/bash -c "$(${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
    '';

    pathsToLink = [ "/Applications" ];
  };

  system = {
    activationScripts.diff = {
      supportsDryActivation = true;
      text = ''
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${pkgs.nix}/bin diff /run/current-system "$systemConfig"
      '';
    };

    # activationScripts are executed every time you boot the system or run `nixos-rebuild` / `darwin-rebuild`.
    activationScripts.postUserActivation.text = ''
      # activateSettings -u will reload the settings from the database and apply them to the current session,
      # so we do not need to logout and login again to make the changes take effect.
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';
  };
}
