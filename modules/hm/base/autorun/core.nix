{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  myargs,
  ...
}:
{
  config =
    let
      inherit (mydefs) stateVersion;
      inherit (pkgs.stdenv) isDarwin;
    in
    {
      home = {
        inherit stateVersion;
        username = myargs.username;
        homeDirectory = if isDarwin then "/Users/${myargs.username}" else "/home/${myargs.username}";
      };

      # Pin user-level registry to local locked inputs for instant ad-hoc command caching
      nix = {
        enable = !isDarwin;
        package = lib.mkIf (!isDarwin) (lib.mkForce pkgs.unstable-nix);
        registry = {
          nixpkgs.flake = inputs.nixpkgs;
          self.flake = inputs.self;
        };
      };

      # bare minimum pacpages
      home.packages = with pkgs; [
        git
        gnumake
        vim
        wget
      ];
    };
}
