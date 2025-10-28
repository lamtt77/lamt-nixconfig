{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.os.base.services.tailscale;
in {
  options = {
    modules.os.base.services.tailscale = {
      enable = lib.mkEnableOption "Tailscale Service";
      loginServer = mkOption {
        type = types.str;
        default = "";
        description = "Custom login server URL for Tailscale";
      };
    };
  };

  config = mkIf cfg.enable {
    # "sudo tailscale up" to manually authenticate
    services.tailscale =
      {
        enable = true;
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        extraUpFlags = mkIf (cfg.loginServer != "") ["--login-server=${cfg.loginServer}"];
      };
  };
}
