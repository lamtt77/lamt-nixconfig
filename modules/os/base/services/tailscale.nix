{
  config,
  lib,
  pkgs,
  myargs,
  ...
}:
with lib;
let
  cfg = config.modules.os.base.services.tailscale;
  isLinux = hasSuffix "-linux" myargs.system;
in
{
  options = {
    modules.os.base.services.tailscale = {
      enable = lib.mkEnableOption "Tailscale Service";
      loginServer = mkOption {
        type = types.str;
        default = "https://ts.lamhub.com";
        description = "Custom login server URL for Tailscale";
      };
      exitNode = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to advertise this node as an exit node";
      };
      authKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to the Tailscale pre-auth key file (e.g. decrypted sops secret)";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.tailscale.enable = true;
    }
    (optionalAttrs isLinux {
      services.tailscale.extraUpFlags = mkMerge [
        (mkIf (cfg.loginServer != "") [ "--login-server=${cfg.loginServer}" ])
        (mkIf cfg.exitNode [ "--advertise-exit-node" ])
      ];

      services.tailscale.authKeyFile = mkIf (cfg.authKeyFile != null) cfg.authKeyFile;

      networking.firewall.checkReversePath = "loose";

      networking.nat = mkIf cfg.exitNode {
        enable = mkDefault true;
        internalInterfaces = [ "tailscale0" ];
      };

      boot.kernel.sysctl = mkIf cfg.exitNode {
        "net.ipv4.ip_forward" = mkDefault 1;
        "net.ipv6.conf.all.forwarding" = mkDefault 1;
      };

      services.resolved = {
        enable = true;
      };
    })
  ]);
}
