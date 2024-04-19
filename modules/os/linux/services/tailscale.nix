{ config, lib, ... }:

with lib;
let
  cfg = config.modules.os.linux.services.tailscale;
in {
  options = with types; {
    modules.os.linux.services.tailscale = {
      enable = mkEnableOption "Tailscale Service";
    };
  };

  config = mkIf cfg.enable {
    # "sudo tailscale up" to manually authenticate
    services.tailscale.enable = true;

    networking = {
      firewall = {
        checkReversePath = "loose";
        allowedUDPPorts = [ config.services.tailscale.port ];
        trustedInterfaces = [ "tailscale0" ];
      };
    };
  };
}
