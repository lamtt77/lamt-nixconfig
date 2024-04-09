# troubleshooting:
# killall gpg-agent
# gpg-agent --daemon

{ inputs, config, lib, pkgs, ... }:

with lib;
let
  inherit (inputs.self.mydefs) gpg-default-key gpg-sshKeys;
  cfg = config.modules.hm.base.gnupg;
  pinentry-program = if pkgs.stdenv.isDarwin
                     then "${pkgs.unstable.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac"
                     else "${pkgs.unstable.pinentry-tty}/bin/pinentry";
in {
  options.modules.hm.base.gnupg = with types; {
    enable = mkEnableOption "GnuPG module";
    cacheTTL = mkOption { type = int; default = 3600; }; # 1h
  };

  config = mkIf cfg.enable {
    programs = let
      fixGpg = ''
        export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
        gpgconf --launch gpg-agent
      '';
      fixGpgFish = ''
        set -gx SSH_AUTH_SOCK $(gpgconf --list-dirs agent-ssh-socket)
        gpgconf --launch gpg-agent
      '';
    in {
      # Start gpg-agent if it's not running or tunneled in
      bash.profileExtra = fixGpg;
      zsh.initExtra = fixGpg;
      fish.shellInit = fixGpgFish;

      gpg = {
        enable = true;
        homedir = "${config.xdg.configHome}/gnupg";
        # TODO
        # publicKeys = [ ];
        settings = {
          default-key = gpg-default-key;
        };
      };
    };

    # this is for supporting darwin/cross platform
    xdg.configFile = {
      "gnupg/gpg-agent.conf" = {
        text = ''
          enable-ssh-support
          default-cache-ttl ${toString cfg.cacheTTL}
          pinentry-program ${pinentry-program}
      '';
      };

      "gnupg/sshcontrol" = {
        text = ''
          ${gpg-sshKeys}
      '';
      };
    };
  };
}
