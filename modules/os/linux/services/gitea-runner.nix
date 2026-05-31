# the runners don't necessarily need to be running Gitea. All we need is an API
# key for Gitea to connect to it and register ourselves as a Runner.
{
  config,
  pkgs,
  lib,
  mydefs,
  ...
}: {
  options.modules.os.linux.services.gitea-runner = {
    enable = lib.mkEnableOption "Gitea Actions runner";
  };

  config = lib.mkIf config.modules.os.linux.services.gitea-runner.enable {
    # Install the gitea-actions-runner package
    environment.systemPackages = [pkgs.gitea-actions-runner];

    # Trust gitea-runner for Nix builds
    nix.settings.trusted-users = ["gitea-runner"];

    # Ensure user and group exist for secrets
    users.users.gitea-runner = {
      isSystemUser = true;
      group = "gitea-runner";
      extraGroups = ["docker"];
    };
    users.groups.gitea-runner = {};

    # Use sops for token
    sops.secrets."gitea-runner-token" = {
      owner = "gitea-runner";
      group = "gitea-runner";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/gitea-actions-runner 0750 gitea-runner gitea-runner -"
    ];

    persist.state.directories = [
      {
        directory = "/var/lib/gitea-actions-runner";
        user = "gitea-runner";
        group = "gitea-runner";
        mode = "0750";
      }
    ];

    systemd.services.gitea-actions-runner = {
      description = "Gitea Actions Runner Registration and Daemon";
      after = ["network.target" "docker.service" "systemd-tmpfiles-setup.service"];
      requires = ["systemd-tmpfiles-setup.service"];
      wantedBy = ["multi-user.target"];
      path = [
        pkgs.bash
        pkgs.git
        pkgs.nix
        pkgs.nodejs
        pkgs.coreutils
      ];
      preStart = ''
        LABELS="ubuntu-latest:docker://gitea/runner-images:ubuntu-latest,ubuntu-22.04:docker://gitea/runner-images:ubuntu-22.04,ubuntu-20.04:docker://gitea/runner-images:ubuntu-20.04,self-hosted:host"

        CURRENT_LABELS=""
        if [ -f /var/lib/gitea-actions-runner/.labels ]; then
          CURRENT_LABELS=$(cat /var/lib/gitea-actions-runner/.labels)
        fi

        if [ ! -f /var/lib/gitea-actions-runner/.runner ] || [ "$CURRENT_LABELS" != "$LABELS" ]; then
          echo "Runner config missing or labels changed. Registering/Re-registering..."
          rm -f /var/lib/gitea-actions-runner/.runner

          # Read the Gitea admin token from secrets
          token=$(cat ${config.sops.secrets."gitea-runner-token".path})

          ${pkgs.gitea-actions-runner}/bin/act_runner register \
            --no-interactive \
            --token "$token" \
            --instance "https://${mydefs.teaURL}" \
            --name "${config.networking.hostName}-runner" \
            --labels "$LABELS"

          echo -n "$LABELS" > /var/lib/gitea-actions-runner/.labels
          echo "Runner registration completed"
        else
          echo "Runner config exists and labels match, skipping registration"
        fi
      '';
      serviceConfig = {
        User = "gitea-runner";
        Group = "gitea-runner";
        WorkingDirectory = "/var/lib/gitea-actions-runner";
        ExecStart = "${pkgs.gitea-actions-runner}/bin/act_runner daemon";
        Environment = [
          "CONFIG_FILE=/var/lib/gitea-actions-runner/.runner"
          "HOME=/var/lib/gitea-actions-runner"
          "ACT_CACHE_DIR=/var/lib/gitea-actions-runner/.cache"
        ];
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
