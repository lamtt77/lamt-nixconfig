# This modules configures it with the expectation that it will be served over an
# SSL-secured or HTTP reverse proxy (best paired with nginx module).
#
# Resources
#   Config: https://docs.gitea.io/en-us/config-cheat-sheet/
#   API:    https://docs.gitea.io/en-us/api-usage/
{
  acmeDomain ? "lamhub.com",
}:
{
  config,
  lib,
  pkgs,
  mydefs,
  myargs,
  ...
}:
with lib;
{
  sops.secrets."smtp-password" = {
    owner = "git";
    group = "gitea";
    mode = "0440";
  };

  environment.systemPackages = with pkgs; [
    sqlite # For database operations in restore scripts
    unzip # For extracting Gitea backup zips
  ];

  # Allows git@... clone addresses rather than gitea@...
  users.users.git = {
    useDefaultShell = true;
    home = "/var/lib/gitea";
    group = "gitea";
    isSystemUser = true;
  };

  users.users.${myargs.username}.extraGroups = [ "gitea" ];
  services = {
    gitea = {
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
        server = {
          DISABLE_ROUTER_LOG = true;
          ROOT_URL = "https://${mydefs.teaURL}/";
          DOMAIN = "${mydefs.teaURL}";
          SSH_DOMAIN = "${mydefs.teaURL}";
        };

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
      mailerPasswordFile = config.sops.secrets."smtp-password".path;
    };

    nginx.virtualHosts."${mydefs.teaURL}" = {
      http2 = true;
      forceSSL = true;
      useACMEHost = acmeDomain;
      root = "/srv/www/${mydefs.teaURL}";
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
  };

  # backup strategy
  systemd.services =
    let
      gitea = "${pkgs.gitea}/bin/gitea";
      appini = "/var/lib/gitea/custom/conf/app.ini";
      bkdir = "/mnt/arthur_z2/Backup/gitea";
      mkBackupService = suffix: schedule: {
        description = "Gitea Backup - ${suffix}";
        serviceConfig = {
          User = "git";
          Group = "gitea";
          Type = "oneshot";
        };
        script = ''
          TARGET_FILE="${bkdir}/teadump-${suffix}.zip"
          if [ ! -w "${bkdir}" ]; then
            echo "Error: ${bkdir} is not writable by user $(whoami)"
            exit 1
          fi
          # Gitea dump fails if file exists, so we must remove it first
          if [ -f "$TARGET_FILE" ]; then
            rm -f "$TARGET_FILE"
          fi
          ${gitea} dump -c ${appini} -f "$TARGET_FILE"
        '';
      };
    in
    {
      gitea-dump-daily = mkBackupService "daily-$(date +\%a)" "";
      gitea-dump-weekly = mkBackupService "weekly-$(date +\%V)" "";
      gitea-dump-monthly = mkBackupService "monthly-$(date +\%b)" "";
      gitea-dump-testing = mkBackupService "testing-$(date +\%a)" "";
    };

  systemd.timers = {
    # gitea-dump-testing = {
    #   wantedBy = ["timers.target"];
    #   timerConfig = {
    #     OnCalendar = "*:0/3";
    #     Persistent = true;
    #   };
    # };
    gitea-dump-daily = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 22:45:00";
        Persistent = true;
      };
    };
    gitea-dump-weekly = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 23:15:00";
        Persistent = true;
      };
    };
    gitea-dump-monthly = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-01 01:00:00";
        Persistent = true;
      };
    };
  };
  persist.state.directories = [
    {
      directory = "/var/lib/gitea";
      user = "git";
      group = "gitea";
      mode = "0750";
    }
  ];
}
