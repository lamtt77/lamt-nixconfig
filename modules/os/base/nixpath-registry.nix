{ inputs, config, lib, ... }:

with lib;
let
  cfg = config.modules.os.base.nixpath-registry;
in {
  options = with types; {
    modules.os.base.nixpath-registry = {
      enable = mkEnableOption "Enable NixPath and Flake Registry";
    };
  };

  config = mkIf cfg.enable {
    # when turn on everything (i.e nix-env) will be locked in flake.lock
    environment.etc.nixpkgs.source = inputs.nixpkgs;
    nix = {
      nixPath = [ "nixpkgs=/etc/${config.environment.etc.nixpkgs.target}" ];
      registry.nixpkgs.flake = inputs.nixpkgs;
      registry.self.flake = inputs.self;
    };
  };
}
