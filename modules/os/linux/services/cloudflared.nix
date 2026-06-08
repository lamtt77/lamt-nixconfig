{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.os.linux.services.cloudflared;
in
{
  options.modules.os.linux.services.cloudflared = {
    enable = mkEnableOption "Cloudflare Tunnel service";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.cloudflared
    ];

    users.users.cloudflared = {
      group = "cloudflared";
      isSystemUser = true;
    };
    users.groups.cloudflared = { };

    services.cloudflared.enable = true;
  };
}
