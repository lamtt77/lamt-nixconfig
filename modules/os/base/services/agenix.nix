{ inputs, config, options, pkgs, lib, username, hostname, ... }:

with lib;
let
  cfg = config.modules.os.base.services.agenix;
in {
  options = with types; {
    modules.os.base.services.agenix = {
      enable = mkEnableOption "Agenix module";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = let inherit (inputs) agenix; in [
      pkgs.age
      pkgs.ssh-to-age
      agenix.packages."${pkgs.system}".default
    ];

    age = let
      inherit (inputs) mysecrets;
      secretsDir = "${mysecrets}/agenix";
      secretsFile = "${secretsDir}/secrets.nix";
      home = config.users.users.${username}.home;
    in {
      secrets =
        if pathExists secretsFile
          # just load the age files belonging to this specific hostname, else it can't decrypt!
        then filterAttrs (n: _: hasPrefix hostname n) (
          mapAttrs' (n: _: nameValuePair (removeSuffix ".age" n) {
            file = "${secretsDir}/${n}";
            owner = mkDefault "root";
          }) (import secretsFile))
        else {};
      identityPaths =
        # default is /etc/ssh/ssh_host_rsa_key and /etc/ssh/ssh_host_ed25519_key
        options.age.identityPaths.default ++ (filter pathExists [
          "${home}/.ssh/id_ed25519"
          "${home}/.ssh/id_rsa"
        ]);
    };
  };
}
