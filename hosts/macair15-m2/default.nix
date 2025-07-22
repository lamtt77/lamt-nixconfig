{ pkgs, ... }: {
  modules.os.base.services.agenix.enable = true;
  modules.os.base.services.wireguard.enable = true;

  modules.os.darwin.services.nfsd.enable = true;

  # # qemu builder
  # nix.linux-builder = {
  #   enable = true;
  #   ephemeral = true;
  #   # config = ({ ... }: {
  #   #   virtualisation.darwin-builder.diskSize = 30 * 1024;
  #   # });
  # };

  # # Disable auto-start, use 'sudo launchctl start org.nixos.linux-builder'
  # launchd.daemons.linux-builder.serviceConfig = {
  #   KeepAlive = lib.mkForce false;
  #   RunAtLoad = lib.mkForce false;
  # };

  environment = {
    extraInit = ''
      # install homebrew if not found
      if [ ! -f "/opt/homebrew/bin/brew" ]; then
         ${pkgs.bash}/bin/bash -c "$(${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
    '';

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
}
