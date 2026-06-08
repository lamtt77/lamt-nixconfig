{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.os.linux.services.headscale;
  derpPort = 3478;
in
{
  options.modules.os.linux.services.headscale = {
    enable = mkEnableOption "Headscale service";
    domain = mkOption {
      type = types.str;
      default = "ts.lamhub.com";
      description = "Domain for Headscale";
    };
    baseDomain = mkOption {
      type = types.str;
      default = "ts.lamhub.lan";
      description = "Internal domain for Headscale nodes";
    };
    users = mkOption {
      type = types.listOf types.str;
      default = [
        "lamt"
        "cloud"
      ];
      description = "List of Headscale users to ensure exist. Other existing users will not be deleted.";
    };
  };

  config = mkIf cfg.enable {
    modules.os.base.services.tailscale.loginServer = "https://${cfg.domain}";

    services.headscale = {
      enable = true;
      port = 8085;
      address = "127.0.0.1";
      settings = {
        server_url = "https://${cfg.domain}";
        metrics_listen_addr = "127.0.0.1:8095";
        logtail = {
          enabled = false;
        };
        log = {
          level = "warn";
        };
        prefixes = {
          v4 = "100.64.0.0/24";
          v6 = "fd7a:115c:a1e0::/48";
        };
        derp = {
          server = {
            enable = true;
            region_id = 999;
            stun_listen_addr = "0.0.0.0:${toString derpPort}";
          };
        };
        dns = {
          base_domain = cfg.baseDomain;
          # false = tailscale only handles ts.lamhub.lan (MagicDNS); system DNS
          # handles everything else. Avoids the ~. catch-all that overrides all
          # DNS on every node and breaks internet access on cloud hosts.
          override_local_dns = false;
          magic_dns = true;
          # Public fallback for all nodes. Each host's system DNS (e.g.
          # 192.168.1.1 on LAN hosts) takes precedence for non-tailnet domains.
          nameservers.global = [
            "1.1.1.1"
            "8.8.8.8"
          ];
        };
        policy = {
          mode = "file";
          path = "${pkgs.writeText "policy.hujson" (
            builtins.toJSON {
              # only 'lamt' accessing full tailnet
              acls = [
                {
                  action = "accept";
                  src = [ "lamt@" ];
                  dst = [ "*:*" ];
                }
              ];
            }
          )}";
        };
      };
    };

    services.nginx.virtualHosts."${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = config.modules.os.linux.services.acme.domain;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8085";
          proxyWebsockets = true;
        };
        "/metrics" = {
          proxyPass = "http://127.0.0.1:8095/metrics";
        };
      };
    };

    # Derp server
    networking.firewall.allowedUDPPorts = [ derpPort ];

    systemd.services.headscale-users = {
      description = "Ensure Headscale users exist";
      wantedBy = [ "multi-user.target" ];
      after = [ "headscale.service" ];
      requires = [ "headscale.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "headscale-users-setup" ''
          # Wait for headscale socket to be ready
          until [ -S /run/headscale/headscale.sock ]; do
            echo "Waiting for headscale.sock..."
            sleep 1
          done

          # Get list of existing users
          EXISTING_USERS=$(${config.services.headscale.package}/bin/headscale users list --output json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[].name' || true)

          # Ensure defined users exist
          for user in ${escapeShellArgs cfg.users}; do
            if echo "$EXISTING_USERS" | grep -q -x "$user"; then
              echo "User $user already exists."
            else
              echo "Creating user $user..."
              ${config.services.headscale.package}/bin/headscale users create "$user"
            fi
          done
        '';
      };
    };
    persist.state.directories = [
      {
        directory = "/var/lib/headscale";
        user = "headscale";
        group = "headscale";
        mode = "0750";
      }
    ];
  };
}
