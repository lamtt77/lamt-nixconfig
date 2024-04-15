# This modules configures it with the expectation that it will be served over an
# SSL-secured or HTTP reverse proxy (best paired with nginx module).
#
# Resources
#   Config: https://docs.gitea.io/en-us/config-cheat-sheet/
#   API:    https://docs.gitea.io/en-us/api-usage/

{ config, lib, ... }:

with lib;
let cfg = config.modules.os.linux.services.gitea;
in {
  options.modules.os.linux.services.gitea = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    age.secrets.avon_gitea-smtp-password.owner = "git";

    # Allows git@... clone addresses rather than gitea@...
    users.users.git = {
      useDefaultShell = true;
      home = "/var/lib/gitea";
      group = "gitea";
      isSystemUser = true;
    };

    user.extraGroups = [ "gitea" ];

    services.gitea = {
      enable = true;
      lfs.enable = true;

      appName = "LamT's Gitea Service";
      user = "git";
      database.user = "git";

      settings = {
        # for SSL-only connectivity, this requires internet facing server with ACME
        # session.COOKIE_SECURE = true;

        # Only log what's important, but Info is necessary for fail2ban to work
        log.LEVEL = "Info";
        database.LOG_SQL = false;
        server.DISABLE_ROUTER_LOG = true;

        server.ROOT_URL = "http://tea2.lamhub.com/";
        server.DOMAIN = "tea2.lamhub.com";
        server.SSH_DOMAIN = "tea2.lamhub.com";

        service.DISABLE_REGISTRATION = true;
        service.ENABLE_BASIC_AUTHENTICATION = false;
        # service.REGISTER_EMAIL_CONFIRM = false;
        # service.REGISTER_MANUAL_CONFIRM = true;

        # zoho supports both 587: smtp+starttls and 465: smtps PROTOCOL
        mailer = {
          ENABLED = true;
          FROM = "info@lamhub.com";
          USER = "info@lamhub.com";
          SMTP_ADDR = "smtp.zoho.com";
          SMTP_PORT = "587";
        };
      };
      mailerPasswordFile = config.age.secrets.avon_gitea-smtp-password.path;

      dump = {
        enable = true;
        interval = "daily";
        backupDir = "/backup/gitea";
      };
    };

    services.nginx.virtualHosts."tea2.lamhub.com" = {
      http2 = true;
      # forceSSL = true;
      # enableACME = true;
      root = "/srv/www/tea2.lamhub.com";
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };

    services.fail2ban.jails.gitea = ''
      enabled = true
      filter = gitea
      banaction = %(banaction_allports)s
      maxretry = 5
    '';

    systemd.tmpfiles.rules = [
      "z ${config.services.gitea.dump.backupDir} 750 git gitea - -"
      "d ${config.services.gitea.dump.backupDir} 750 git gitea - -"
    ];
  };
}
