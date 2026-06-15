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

      # Disable Home Manager manuals generation to speed up evaluation
      manual = {
        html.enable = false;
        manpages.enable = false;
        json.enable = false;
      };

      # Pin user-level registry to local locked inputs for instant ad-hoc command caching
      nix = {
        enable = !isDarwin;
        package = lib.mkIf (!isDarwin) (lib.mkForce pkgs.unstable-nix);
        registry = {
          nixpkgs.flake = inputs.nixpkgs;
        };
      };

      # bare minimum packages
      home.packages = with pkgs; [
        git
        gnumake
        vim
        wget
      ];
    };
}
