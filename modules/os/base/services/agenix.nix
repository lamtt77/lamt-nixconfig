{ inputs, config, options, pkgs, lib, username, hostname, ... }:

with lib;
let
  cfg = config.modules.os.base.services.agenix;
in {
  options = with types; {
    modules.os.base.services.agenix = {
      enable = mkEnableOption "Agenix Module";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = let inherit (inputs) agenix; in [
      pkgs.age
      pkgs.ssh-to-age
      agenix.packages."${pkgs.system}".default
    ];

    age = let
      # inherit (inputs) mysecrets;
      # secretsDir = "${mysecrets}/agenix";
      # home = config.users.users."${username}".home;
      inherit (inputs) self;
      secretsDir = "${self}/secrets/agenix";
      secretsFile = "${secretsDir}/secrets.nix";
    in {
      secrets =
        # just load the age files from our current hostname, else it can't decrypt!
        if pathExists secretsFile
        then filterAttrs (n: _: hasPrefix "${hostname}/" n) (
          mapAttrs' (n: _: nameValuePair (removeSuffix ".age" n) {
            file = "${secretsDir}/${n}";
            owner = mkDefault username;
          }) (import secretsFile))
        else {};
      # default: /etc/ssh/ssh_host_rsa_key and /etc/ssh/ssh_host_ed25519_key
      identityPaths =  ["/etc/ssh/id_agenix"] ++ options.age.identityPaths.default;
    };
  };
}
