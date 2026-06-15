{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  ...
}:
with lib;
let
  nas = mydefs.nasIp;
  cfg = config.services.arthur-backup;
  arthurBackup = pkgs.callPackage ../../../../../pkgs/arthur-backup { };
in
{
  options.services.arthur-backup = {

    user = mkOption {
      type = types.str;
      default = "backup";
      description = "User to run the backup service";
    };

    configFile = mkOption {
      type = types.path;
      default = ../../../../../pkgs/arthur-backup/universal_backup.conf;
      description = "Path to the backup configuration file";
    };

    bkrcFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the backup config file (.backuprc)";
    };

    logDir = mkOption {
      type = types.path;
      default = "/var/log/backup";
      description = "Directory for backup logs";
    };

    schedules = mkOption {
      type = types.attrsOf types.str;
      default = {
        daily = "*-*-* 23:00:00";
        weekly = "Mon *-*-* 23:30:00";
        monthly = "*-*-01 01:15:00";
        quarterly = "*-01,04,07,10-01 02:15:00";
        yearly = "*-01-01 01:00:00";
      };
      description = "Systemd calendar schedules for backup scopes";
    };

    mountPoints = mkOption {
      type = types.attrsOf types.str;
      default = {
        "/mnt/arthur_z2/Boot" = "${nas}:/mnt/arthur_z2/Boot";
        "/mnt/arthur_z2/Backup" = "${nas}:/mnt/arthur_z2/Backup";
        "/mnt/arthur_z2/Data" = "${nas}:/mnt/arthur_z2/Data";
      };
      description = "Mount points for backup datasets (device paths)";
    };
  };

  config = {
    sops = {
      secrets = {
        # SOPS secrets for backup
        "backup_rclone_password" = {
          mode = "0400";
          owner = cfg.user;
          group = cfg.user;
        };
        "backup_rclone_config" = {
          mode = "0400";
          owner = cfg.user;
          group = cfg.user;
        };
        "backup_restic_password" = {
          mode = "0400";
          owner = cfg.user;
          group = cfg.user;
        };
        "backup_borg_pass" = {
          mode = "0400";
          owner = cfg.user;
          group = cfg.user;
        };
      };
    };

    environment = {
      # Generate .backuprc file
      etc."backuprc" = {
        target = "backuprc";
        text = ''
          export LOG_DIR=${cfg.logDir}
          export DATA_DIR=/mnt/arthur_z2/Data
          export BACKUP_DIR=/mnt/arthur_z2/Backup
          export BOOT_DIR=/mnt/arthur_z2/Boot
          export RCLONE_CONFIG=/var/lib/${cfg.user}/rclone.conf
          export RCLONE_PASSWORD_COMMAND='head -1 ${config.sops.secrets."backup_rclone_password".path}'
          export RESTIC_PASSWORD_COMMAND='cat ${config.sops.secrets."backup_restic_password".path}'
          export BORG_PASSCOMMAND='cat ${config.sops.secrets."backup_borg_pass".path}'
          export MAILTO=lam@lamhub.com
          export MAILFROM=${mydefs.infoEmail}
        '';
        mode = "0444";
      };

      # Ensure dependencies are installed
      systemPackages =
        with pkgs;
        [
          rclone
          restic
          borgbackup
          msmtp
        ]
        ++ [ arthurBackup ];

      # msmtp configuration for email reports
      etc."msmtprc".text = ''
        account default
        host ${mydefs.relayHost}
        port 587
        from ${mydefs.infoEmail}
        user ${mydefs.infoEmail}
        passwordeval cat ${config.sops.secrets."smtp-password".path}
        tls on
        tls_starttls on
        auth on
        logfile /var/log/backup/msmtp.log
      '';
    };

    services = {
      # Enable NFS client
      rpcbind.enable = true;
      arthur-backup.bkrcFile = "/etc/backuprc";

      # Logrotate configuration
      logrotate = {
        enable = true;
        settings.backup = {
          files = "${cfg.logDir}/*.log";
          frequency = "weekly";
          rotate = 52;
          compress = true;
          missingok = true;
          notifempty = true;
        };
      };
    };

    # Mount points for backup datasets
    fileSystems = mkMerge (
      mapAttrsToList (mountPoint: device: {
        "${mountPoint}" = {
          inherit device;
          fsType = if lib.hasPrefix "${nas}" device then "nfs" else "none";
          options = if lib.hasPrefix "${nas}" device then [ "defaults" ] else [ "bind" ];
        };
      }) cfg.mountPoints
    );

    # Create backup user
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/${cfg.user}";
      createHome = true;
      extraGroups = [ "gitea" ];
    };
    users.groups.${cfg.user} = { };

    systemd = {
      # Create log directory
      tmpfiles.rules = [
        "d ${cfg.logDir} 0750 ${cfg.user} ${cfg.user} -"
      ];

      # Systemd services and timers for each scope
      services = mkMerge (
        mapAttrsToList (scope: schedule: {
          "arthur-backup-${scope}" = {
            description = "Arthur Universal Backup - ${scope}";
            serviceConfig = {
              Type = "oneshot";
              User = cfg.user;
              Environment = [
                "PATH=/run/current-system/sw/bin:/bin"
              ];
              ExecStart = "${pkgs.runCommand "run-backup-${scope}" { } ''
                cat > $out << 'EOF'
                #!/run/current-system/sw/bin/bash
                set -euo pipefail
                cd ${arthurBackup}/bin
                cp -f ${config.sops.secrets."backup_rclone_config".path} /var/lib/${cfg.user}/rclone.conf
                source ${cfg.bkrcFile}
                ./arthur_universal_backup --${scope}
                EOF
                chmod +x $out
              ''}";
            };
          };
        }) cfg.schedules
      );

      timers = mkMerge (
        mapAttrsToList (scope: schedule: {
          "arthur-backup-${scope}" = {
            description = "Timer for Arthur Universal Backup - ${scope}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = schedule;
              Persistent = true;
            };
          };
        }) cfg.schedules
      );
    };
  };
}
