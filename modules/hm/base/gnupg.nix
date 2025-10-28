# troubleshooting issues: such as no pinentry
# pkill gpg-agent OR killall gpg-agent
# gpg-agent --daemon
#
# feature: work on both Linux and MacOS, unlike the stock home-manager
{
  config,
  lib,
  pkgs,
  mydefs,
  ...
}:
with lib; let
  inherit (mydefs) gpgDefaultKey gpgSshKeygrip;
  cfg = config.modules.hm.base.gnupg;
  pinentry-program =
    if pkgs.stdenv.isDarwin
    then "${lib.getExe pkgs.pinentry_mac}"
    else "${lib.getExe pkgs.pinentry-gnome3}";
in {
  options.modules.hm.base.gnupg = with types; {
    enable = mkEnableOption "GnuPG module";
    defaultCacheTTL = mkOption {
      type = int;
      default = 34560000;
    };
    maxCacheTTL = mkOption {
      type = int;
      default = 34560000;
    };
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

        # # If set `mutableTrust` to false, the path $GNUPGHOME/trustdb.gpg will be overwritten on each activation.
        # # Thus we can only update trsutedb.gpg via home-manager.
        # mutableTrust = false;
        # # If set `mutableKeys` to false, the path $GNUPGHOME/pubring.kbx will become an immutable link to the Nix store, denying modifications.
        # # Thus we can only update pubring.kbx via home-manager
        # mutableKeys = false;

        settings = {
          default-key = gpgDefaultKey;
          keyserver = "hkps://keys.openpgp.org";
          keyserver-options = "no-auto-key-retrieve";
        };

        scdaemonSettings = {
          disable-ccid = true;
        };
      };
    };

    # this is for supporting darwin/cross platform, headless pinentry
    xdg.configFile = mkIf cfg.enableSSHSupport {
      "gnupg/gpg-agent.conf".text = ''
        default-cache-ttl ${toString cfg.defaultCacheTTL}
        max-cache-ttl ${toString cfg.maxCacheTTL}
        default-cache-ttl-ssh ${toString cfg.defaultCacheTTL}
        max-cache-ttl-ssh ${toString cfg.maxCacheTTL}
        enable-ssh-support
        extra-socket ${config.xdg.configHome}/gnupg/S.gpg-agent.extra
        pinentry-program ${pinentry-program}
      '';

      "gnupg/sshcontrol".text = ''
        ${gpgSshKeygrip}
      '';
    };
  };
}
