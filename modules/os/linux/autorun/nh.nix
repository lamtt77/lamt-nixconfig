# NOTE: nh does not run on Darwin at the moment

{ inputs, pkgs, username, ... }: let
  inherit (inputs.self) mydefs;
in {
  imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/programs/nh.nix" ];

  programs.nh = {
    enable = true;
    package = pkgs.unstable.nh;
    flake = if pkgs.stdenv.isDarwin
            then "/Users/${username}/${mydefs.myRepoName}"
            else "/home/${username}/${mydefs.myRepoName}";
    clean = {
      enable = true;
      extraArgs = "--keep-since 14d --keep 5";
    };
  };
}
