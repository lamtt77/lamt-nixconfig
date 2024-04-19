{ config, lib, ... }:

with lib;
let
  cfg = config.modules.os.linux.services.openssh;
in {
  options = with types; {
    modules.os.linux.services.openssh = {
      enable = mkEnableOption "OpenSSH service";
    };
  };

  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    programs.ssh.startAgent = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
