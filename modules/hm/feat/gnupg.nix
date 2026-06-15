# troubleshooting issues: such as no pinentry
# pkill gpg-agent OR killall gpg-agent
# gpg-agent --daemon
#
# feature: work on both Linux and MacOS, unlike the stock home-manager
{
  defaultCacheTTL ? 34560000,
  maxCacheTTL ? 34560000,
  enableSSHSupport ? false,
}:
{
  config,
  lib,
  pkgs,
  mydefs,
  ...
}:
let
  inherit (mydefs) gpgDefaultKey gpgSshKeygrip;
  pinentry-program =
    if pkgs.stdenv.isDarwin then
      "${lib.getExe pkgs.pinentry_mac}"
    else
      "${lib.getExe pkgs.pinentry-gnome3}";
in
{
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
  };

  programs =
    let
      fixGpg = ''
        gpgconf --launch gpg-agent
        gpg-connect-agent updatestartuptty /bye > /dev/null
      '';
    in
    {
      # Start gpg-agent if it's not running or tunneled in
      bash.profileExtra = fixGpg;
      zsh.initContent = fixGpg;

      gpg = {
        enable = true;
        homedir = "${config.xdg.configHome}/gnupg";

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
  xdg.configFile = lib.mkIf enableSSHSupport {
    "gnupg/gpg-agent.conf".text = ''
      default-cache-ttl ${toString defaultCacheTTL}
      max-cache-ttl ${toString maxCacheTTL}
      default-cache-ttl-ssh ${toString defaultCacheTTL}
      max-cache-ttl-ssh ${toString defaultCacheTTL}
      enable-ssh-support
      extra-socket ${config.xdg.configHome}/gnupg/S.gpg-agent.extra
      pinentry-program ${pinentry-program}
    '';

    "gnupg/sshcontrol".text = ''
      ${gpgSshKeygrip}
    '';
  };
}
