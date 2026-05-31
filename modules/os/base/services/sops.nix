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
      defaultSopsFile =
        let
          secretsFile = "${inputs.self}/secrets/sops/${myargs.hostname}.yaml";
          fallbackFile = ./dummy-secrets.yaml;
        in
          if builtins.pathExists secretsFile then secretsFile else fallbackFile;
      validateSopsFiles = builtins.pathExists "${inputs.self}/secrets/sops/${myargs.hostname}.yaml";
      age.sshKeyPaths = lib.mkForce [cfg.ageKeyFile];
    };

    system.activationScripts.setupSecrets =
      let
        secretsFile = "${inputs.self}/secrets/sops/${myargs.hostname}.yaml";
      in
        mkIf (!builtins.pathExists secretsFile) (mkForce ''
          echo "========================================================================="
          echo "WARNING: SOPS secrets file was missing during build:"
          echo "  ${secretsFile}"
          echo "Bypassing secrets installation. Active secrets in /run/secrets remain for now,"
          echo "but they WILL NOT persist across reboots!"
          echo "Please redeploy from a management host containing the secrets repository."
          echo "========================================================================="
        '');
  };
}
