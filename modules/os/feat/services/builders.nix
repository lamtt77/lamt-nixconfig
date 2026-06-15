{
  config,
  lib,
  pkgs,
  mydefs,
  inputs,
  ...
}:
{
  # Define the secret for the builder key
  sops.secrets.nix_builder_key = {
    owner = "root";
    mode = "0600";
  };

  nix.distributedBuilds = true;

  nix.buildMachines = [
    {
      hostName = inputs.self.deploymentHosts.utils.deployment.targetIp;
      system = "x86_64-linux";
      protocol = "ssh-ng";
      maxJobs = 8;
      speedFactor = 2;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
      sshUser = "deploy";
      sshKey = config.sops.secrets.nix_builder_key.path;
    }
  ];

  nix.settings.builders-use-substitutes = true;

  # Workaround for nix-darwin not generating /etc/nix/machines automatically
  # when using Determinate Systems installer or due to activation issues.
  environment.etc."nix/machines" = lib.mkIf pkgs.stdenv.isDarwin {
    text = lib.concatMapStringsSep "\n" (
      machine:
      "${machine.protocol}://${machine.sshUser}@${machine.hostName} ${machine.system} ${machine.sshKey} ${toString machine.maxJobs} ${toString machine.speedFactor} ${lib.concatStringsSep "," machine.supportedFeatures} - -"
    ) config.nix.buildMachines;
  };

  # Configure global SSH to allow Nix daemon to connect to builder without host key verification
  programs.ssh.extraConfig = ''
    Host ${inputs.self.deploymentHosts.utils.deployment.targetIp}
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
  '';
}
