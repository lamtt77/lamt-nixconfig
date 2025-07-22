{ inputs, config, lib, ... }:

with lib;
let
  cfg = config.modules.os.linux.services.openssh;
  inherit (inputs.self) mydefs;
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
        # Automatically remove stale sockets
        StreamLocalBindUnlink = "yes";
        # Allow forwarding ports to everywhere
        # GatewayPorts = "clientspecified";
      };
      knownHosts = {
        "github.com".publicKey = mydefs.githubPubkey;
        "tea.lamhub.com".publicKey = mydefs.teaPubkey;
      };
    };

    # Keep SSH_AUTH_SOCK when sudo'ing
    security.sudo.extraConfig = ''
      Defaults env_keep+=SSH_AUTH_SOCK
    '';

    # programs.ssh.startAgent = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
