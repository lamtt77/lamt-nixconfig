{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.xrdp = {
    enable = true;
    # Allow RDP connections through the NixOS firewall
    openFirewall = true;
  };
}
