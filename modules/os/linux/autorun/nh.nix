# NOTE: nh does not have programs options on Darwin at the moment

{ inputs, pkgs, username, ... }: let
  inherit (inputs.self) mydefs;
in {
  programs.nh = {
    enable = true;
    flake = if pkgs.stdenv.isDarwin
            then "/Users/${username}/${mydefs.myRepoName}"
            else "/home/${username}/${mydefs.myRepoName}";
    clean = {
      enable = true;
      extraArgs = "--keep-since 10d --keep 3";
    };
  };
}
