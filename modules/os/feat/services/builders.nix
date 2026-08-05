{
  config,
  lib,
  pkgs,
  mydefs,
  my,
  ...
}:
let
  # Builder endpoint is owned by infra/site.nix site.hosts.utils, not by OS options.
  utilsTargetIp = my.hostAddress "utils";

  # One line per builder for nix.conf `builders` / /etc/nix/machines.
  # Field order (nix manual):
  #   URI  systems  ssh-key  max-jobs  speed-factor  features  mandatory-features  ssh-public-host-key
  # Use "-" for an empty optional field.
  # Note: attr `or` only fills when the attribute is missing, not when it is null.
  emptyOr = value: value == null || value == "" || value == [ ];
  joinOrDash = values: if emptyOr values then "-" else lib.concatStringsSep "," values;

  formatBuildMachine =
    machine:
    let
      uri = "${machine.protocol}://${machine.sshUser}@${machine.hostName}";
      systems =
        if !(emptyOr (machine.systems or [ ])) then
          lib.concatStringsSep "," machine.systems
        else
          machine.system;
      features = joinOrDash (machine.supportedFeatures or [ ]);
      mandatoryFeatures = joinOrDash (machine.mandatoryFeatures or [ ]);
      publicHostKey = if emptyOr (machine.publicHostKey or null) then "-" else machine.publicHostKey;
    in
    lib.concatStringsSep " " [
      uri
      systems
      machine.sshKey
      (toString machine.maxJobs)
      (toString machine.speedFactor)
      features
      mandatoryFeatures
      publicHostKey
    ];

  machinesFileText = lib.concatMapStringsSep "\n" formatBuildMachine config.nix.buildMachines + "\n";
in
{
  # Define the secret for the builder key
  sops.secrets.nix_builder_key = {
    owner = "root";
    mode = "0600";
  };

  nix.distributedBuilds = true;

  nix.buildMachines = [
    {
      hostName = utilsTargetIp;
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

  # nix-darwin + Determinate does not always materialize /etc/nix/machines
  # from nix.buildMachines; write it explicitly on Darwin.
  environment.etc."nix/machines" = lib.mkIf pkgs.stdenv.isDarwin {
    text = machinesFileText;
  };

  # Allow the Nix daemon to reach the builder without interactive host-key prompts.
  programs.ssh.extraConfig = ''
    Host ${utilsTargetIp}
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
  '';
}
