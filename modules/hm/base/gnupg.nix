# troubleshooting issues: such as no pinentry
# pkill gpg-agent OR killall gpg-agent
# gpg-agent --daemon
#
# feature: work on both Linux and MacOS, unlike the stock home-manager

{ inputs, config, lib, pkgs, ... }:

with lib;
let
  inherit (inputs) self;
  inherit (self.mydefs) gpgDefaultKey gpgSshKeygrip;
  cfg = config.modules.hm.base.gnupg;
  pinentry-program = if pkgs.stdenv.isDarwin
                     then "${pkgs.unstable.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac"
                     else "${pkgs.unstable.pinentry-curses}/bin/pinentry";
in {
  options.modules.hm.base.gnupg = with types; {
    enable = mkEnableOption "GnuPG module";
    defaultCacheTTL = mkOption { type = int; default = 34560000; };
    maxCacheTTL = mkOption { type = int; default = 34560000; };
    enableSSHSupport = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    home.sessionVariables = {
      SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
    };

    programs = let
      fixGpg = ''
        gpgconf --launch gpg-agent
        gpg-connect-agent updatestartuptty /bye >/dev/null
      '';
    in {
      # Start gpg-agent if it's not running or tunneled in
      bash.profileExtra = fixGpg;
      zsh.initContent = fixGpg;

      gpg = {
        enable = true;
        homedir = "${config.xdg.configHome}/gnupg";

        # If set `mutableTrust` to false, the path $GNUPGHOME/trustdb.gpg will be overwritten on each activation.
        # Thus we can only update trsutedb.gpg via home-manager.
        mutableTrust = false;
        # If set `mutableKeys` to false, the path $GNUPGHOME/pubring.kbx will become an immutable link to the Nix store, denying modifications.
        # Thus we can only update pubring.kbx via home-manager
        mutableKeys = false;

        publicKeys = [
          {
            source = "${self}/profiles/lamt/lamtt77-gmail-gpg-FULL-LamT-2024.pub.asc";
            trust = 5; # ultimate trust
          }
        ];
        settings = {
          default-key = gpgDefaultKey;
        };
      };
    };

    # this is for supporting darwin/cross platform, headless pinentry
    # extra-socket ${config.xdg.configHome}/gnupg/S.gpg-agent.extra
    xdg.configFile = mkIf (cfg.enableSSHSupport) {
      "gnupg/gpg-agent.conf" = {
        text = ''
          default-cache-ttl ${toString cfg.defaultCacheTTL}
          max-cache-ttl ${toString cfg.maxCacheTTL}
          default-cache-ttl-ssh ${toString cfg.defaultCacheTTL}
          max-cache-ttl-ssh ${toString cfg.maxCacheTTL}
          enable-ssh-support
          pinentry-program ${pinentry-program}
      '';
      };

      "gnupg/sshcontrol" = {
        text = ''
          ${gpgSshKeygrip}
      '';
      };
    };
  };
}
