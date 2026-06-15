{
  loginServer ? "https://ts.lamhub.com",
  exitNode ? false,
  authKey ? null,
}:
{
  config,
  pkgs,
  lib,
  myargs,
  ...
}:
with lib;
let
  isLinux = hasSuffix "-linux" myargs.system;
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
      (mkIf (loginServer != "") [ "--login-server=${loginServer}" ])
      (mkIf exitNode [ "--advertise-exit-node" ])
    ];

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
