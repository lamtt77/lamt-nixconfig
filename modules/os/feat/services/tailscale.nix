{
  loginServer ? "https://ts.lamhub.com",
  router ? null,
  authKey ? null,
}:
{
  config,
  pkgs,
  lib,
  myargs,
  inputs,
  ...
}:
with lib;
let
  isLinux = hasSuffix "-linux" myargs.system;
  tailnet = if router == null then null else import ../../base/services/tailnet.nix;
  routerRecord =
    if router == null then
      null
    else
      tailnet.routers.${router} or (throw "Unknown Tailnet router selector '${router}'");
  exitNode = routerRecord != null && routerRecord.exitNode;
  advertiseRoutes =
    if routerRecord == null then
      [ ]
    else
      concatMap (
        group: tailnet.routeGroups.${group}.routes or (throw "Unknown Tailnet route group '${group}'")
      ) routerRecord.routeGroups;
  routeAdvertisementFlag = "--advertise-routes=${concatStringsSep "," advertiseRoutes}";
  routeAdvertisementFlags = concatStringsSep " " (
    optional exitNode "--advertise-exit-node=true"
    ++ optional (routerRecord != null) routeAdvertisementFlag
  );
  reconcileCommand = "${pkgs.tailscale}/bin/tailscale set ${routeAdvertisementFlags}";
in
mkMerge [
  {
    services.tailscale.enable = true;
  }
  (mkIf isLinux {
    # Direct, unconditional declarations (self-sufficient) if authKey is provided
    sops.secrets = mkIf (authKey != null) {
      ${authKey} = { };
    };
    services.tailscale.authKeyFile = mkIf (authKey != null) config.sops.secrets.${authKey}.path;

    services.tailscale.extraUpFlags = mkMerge [
      # A router's tag comes from its Headscale pre-auth key. Reset stale
      # client-side preferences from an earlier enrollment before autoconnect
      # applies the complete declarative route configuration.
      (mkIf (routerRecord != null) [ "--reset" ])
      (mkIf (loginServer != "") [ "--login-server=${loginServer}" ])
      (mkIf exitNode [ "--advertise-exit-node" ])
      (mkIf (routerRecord != null) [ routeAdvertisementFlag ])
    ];

    # Router tags are assigned by the Headscale pre-auth key. Do not also pass
    # `--advertise-tags`: Headscale validates that as a separate request and
    # rejects it for a tagged key. Reconcile only mutable route advertisements.
    systemd.services.tailscale-advertise = mkIf (routeAdvertisementFlags != "") {
      description = "Reconcile Tailscale route advertisements";
      after = [ "tailscaled-autoconnect.service" ];
      wants = [ "tailscaled-autoconnect.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        for attempt in $(seq 1 30); do
          if ${reconcileCommand}; then
            exit 0
          fi
          sleep 2
        done

        exit 1
      '';
    };

    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
    networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

    networking.nat = mkIf exitNode {
      enable = mkDefault true;
      internalInterfaces = [ "tailscale0" ];
    };

    boot.kernel.sysctl = mkIf exitNode {
      "net.ipv4.ip_forward" = mkDefault 1;
      "net.ipv6.conf.all.forwarding" = mkDefault 1;
    };

    services.resolved = {
      enable = true;
    };
  })
]
