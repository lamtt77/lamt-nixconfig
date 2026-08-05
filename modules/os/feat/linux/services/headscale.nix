{
  domain ? "ts.lamhub.com",
  baseDomain ? "ts.lamhub.lan",
  users ? [
    "lamt"
    "cloud"
    "fcm"
  ],
  # Must match the cert name created by the acme module (i.e. the acme domain arg)
  acmeDomain ? "lamhub.com",
}:
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  derpPort = 3478;
  tailnet = import ../../../base/services/tailnet.nix;
  routers = builtins.attrValues tailnet.routers;
  routesFor =
    record:
    lib.concatMap (
      group: tailnet.routeGroups.${group}.routes or (throw "Unknown Tailnet route group '${group}'")
    ) record.routeGroups;
  tagOwners = lib.mapAttrs (_: records: lib.unique (map (record: "${record.owner}@") records)) (
    lib.groupBy (record: record.tag) routers
  );
  routerTags = lib.unique (map (record: record.tag) routers);
  exitNodeTags = lib.unique (map (record: record.tag) (lib.filter (record: record.exitNode) routers));
  routeApprovals = lib.foldl' (
    approvals: record:
    lib.foldl' (
      routes: route: routes // { ${route} = lib.unique ((routes.${route} or [ ]) ++ [ record.tag ]); }
    ) approvals (routesFor record)
  ) { } routers;
in
{
  services.headscale = {
    enable = true;
    port = 8085;
    address = "127.0.0.1";
    settings = {
      server_url = "https://${domain}";
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
        base_domain = baseDomain;
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
            inherit tagOwners;
            autoApprovers = {
              exitNode = exitNodeTags;
              routes = routeApprovals;
            };
            acls = [
              {
                action = "accept";
                src = [ "lamt@" ];
                dst = [ "*:*" ];
              }
              # Tagged routers are distinct from user-owned nodes in Headscale's
              # policy compiler, so expose every declared router explicitly.
              {
                action = "accept";
                src = [ "lamt@" ];
                dst = map (tag: "${tag}:*") routerTags;
              }
              {
                action = "accept";
                src = [ "lamt@" ];
                dst = map (route: "${route}:*") (builtins.attrNames routeApprovals);
              }
              {
                action = "accept";
                src = [ "lamt@" ];
                dst = [ "autogroup:internet:*" ];
              }
            ];
          }
        )}";
      };
    };
  };

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = acmeDomain;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:8085";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
        '';
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
        for user in ${lib.escapeShellArgs users}; do
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
}
