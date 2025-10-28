{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.os.linux.services.headscale;
  derpPort = 3478;
in {
  options.modules.os.linux.services.headscale = {
    enable = mkEnableOption "Headscale service";
    domain = mkOption {
      type = types.str;
      default = "ts.lamhub.com";
      description = "Domain for Headscale";
    };
  };

  config = mkIf cfg.enable {
    modules.os.base.services.tailscale.loginServer = "https://${cfg.domain}";

    services.headscale = {
      enable = true;
      port = 8085;
      address = "127.0.0.1";
      settings = {
        server_url = "https://ts.lamhub.com";
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
          base_domain = cfg.domain;
          magic_dns = true;
          search_domains = [cfg.domain];
          nameservers = {
            global = ["1.1.1.1" "8.8.8.8"];
          };
        };
      };
    };

    services.nginx.virtualHosts."ts.lamhub.com" = {
      forceSSL = true;
      enableACME = true;
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
    networking.firewall.allowedUDPPorts = [derpPort];
  };
}
