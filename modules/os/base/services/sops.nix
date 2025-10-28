{
  inputs,
  config,
  pkgs,
  lib,
  myargs,
  ...
}:
with lib; let
  cfg = config.modules.os.base.services.sops;
in {
  options = with types; {
    modules.os.base.services.sops = {
      enable = mkEnableOption "SOPS Module";
      ageKeyFile = mkOption {
        type = str;
        default = "/etc/ssh/ssh_host_ed25519_key";
        description = "Path to the SSH key file for age";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      sops
      age
      ssh-to-age
    ];

    sops = {
      defaultSopsFile = "${inputs.self}/secrets/sops/${myargs.hostname}.yaml";
      age.sshKeyPaths = [cfg.ageKeyFile];
    };
  };
}
