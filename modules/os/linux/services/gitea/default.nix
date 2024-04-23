# This modules configures it with the expectation that it will be served over an
# SSL-secured or HTTP reverse proxy (best paired with nginx module).
#
# Resources
#   Config: https://docs.gitea.io/en-us/config-cheat-sheet/
#   API:    https://docs.gitea.io/en-us/api-usage/

{ inputs, config, lib, pkgs, ... }:

with lib;
let
  inherit (inputs.self) mydefs;
  cfg = config.modules.os.linux.services.gitea;
in {
  options.modules.os.linux.services.gitea = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    age.secrets.avon_smtp-password.owner = "git";

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
      database.type = "sqlite3";

      settings = {
        actions.ENABLED = true;
        metrics.ENABLED = true;

        # for SSL-only connectivity, this requires internet facing server with ACME
        # session.COOKIE_SECURE = true;

        # Only log what's important, but Info is necessary for fail2ban to work
        log.LEVEL = "Info";
        database.LOG_SQL = false;
        server.DISABLE_ROUTER_LOG = true;

        server.ROOT_URL = "http://tea.lamhub.com/";
        server.DOMAIN = "tea.lamhub.com";
        server.SSH_DOMAIN = "tea.lamhub.com";

        service.DISABLE_REGISTRATION = true;
        service.ENABLE_BASIC_AUTHENTICATION = false;
        # service.REGISTER_EMAIL_CONFIRM = false;
        # service.REGISTER_MANUAL_CONFIRM = true;

        repository = {
          ENABLE_PUSH_CREATE_USER = true;
          ENABLE_PUSH_CREATE_ORG = true;
          DEFAULT_BRANCH = "main";
        };

        # zoho supports both 587: smtp+starttls and 465: smtps PROTOCOL
        mailer = {
          ENABLED = true;
          FROM = mydefs.infoEmail;
          USER = mydefs.infoEmail;
          SMTP_ADDR = mydefs.relayHost;
          SMTP_PORT = mydefs.relayPort;
        };
      };
      mailerPasswordFile = config.age.secrets.avon_smtp-password.path;
    };

    # backup strategy
    services.cron = let
      gitea = "${pkgs.gitea}/bin/gitea";
      appini = "/var/lib/gitea/custom/conf/app.ini";
      bkdir = "/mnt/Backup/gitea";
    in {
      enable = true;
      # NOTE: using double-quote will need escape for special characters: slash...
      systemCronJobs = [''
        # uncomment for testing every 3 minutes
        # */3 * * * *  git ${gitea} dump -c ${appini} -f ${bkdir}/teadump-testing-$(date +\%a).zip
        # Daily at 01:00AM: 7-day rolling backup
        00 01 * * *  git ${gitea} dump -c ${appini} -f ${bkdir}/teadump-daily-$(date +\%a).zip
        # Weekly on sunday (0)
        00 00 * * 0  git ${gitea} dump -c ${appini} -f ${bkdir}/teadump-weekly-$(date +\%V).zip
        # Monthly on the first day (1)
        00 00 1 * *  git ${gitea} dump -c ${appini} -f ${bkdir}/teadump-monthly-$(date +\%b).zip
      ''];
    };
    # nas nfs share
    fileSystems."/mnt/Backup" = {
      device = "${mydefs.nas}:/mnt/arthur_z2/Backup";
      fsType = "nfs";
    };

    services.nginx.virtualHosts."tea.lamhub.com" = {
      http2 = true;
      # forceSSL = true;
      # enableACME = true;
      root = "/srv/www/tea.lamhub.com";
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };

  };
}
