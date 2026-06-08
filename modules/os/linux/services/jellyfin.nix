# alternative to Plex
{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.modules.os.linux.services.jellyfin;
in
{
  options.modules.os.linux.services.jellyfin = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    services.jellyfin.enable = true;

    networking.firewall = {
      allowedTCPPorts = [ 8096 ];
      allowedUDPPorts = [ 8096 ];
    };

    user.extraGroups = [ "jellyfin" ];
  };
}
