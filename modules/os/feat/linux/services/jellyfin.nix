# alternative to Plex
{ lib, config, ... }:
{
  services.jellyfin.enable = true;

  networking.firewall = {
    allowedTCPPorts = [ 8096 ];
    allowedUDPPorts = [ 8096 ];
  };

  user.extraGroups = [ "jellyfin" ];
}
