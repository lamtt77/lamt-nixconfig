{
  ageKeyFile ? "/etc/ssh/ssh_host_ed25519_key",
}:
{
  config,
  pkgs,
  lib,
  myargs,
  inputs,
  ...
}:
let
  # Secrets are staged by the installer into a host-specific secret input
  # path at build time, then deployed via sops-install-secrets at activation time.
  secretsStorePath = inputs.installer-secret + "/${myargs.hostname}.yaml";
  secretsExists = builtins.pathExists secretsStorePath;
in
{
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];

  sops = {
    defaultSopsFile = if secretsExists then secretsStorePath else ./dummy-secrets.yaml;
    # Always false: the installer manages secret delivery; the sops NixOS
    # module must not validate secrets files during derivation build because
    # the build may run on a remote builder that never sees the secrets tree.
    validateSopsFiles = false;
    age.sshKeyPaths = lib.mkForce [ ageKeyFile ];
  };

  system.activationScripts.setupSecrets = lib.mkIf (!secretsExists) (
    lib.mkForce ''
      echo "========================================================================="
      echo "WARNING: SOPS secrets file was missing during build."
      echo "  Expected staged input: installer-secret/${myargs.hostname}.yaml"
      echo "  Source custody is site-scoped (for this repository: bar/hosts/${myargs.hostname}/)."
      echo "Bypassing secrets installation. Active secrets in /run/secrets remain"
      echo "for now, but they WILL NOT persist across reboots!"
      echo "Please redeploy from a management host containing the secrets repository."
      echo "========================================================================="
    ''
  );
}
