# NOTE: nh does not have programs options on Darwin at the moment
{
  inputs,
  config,
  pkgs,
  mydefs,
  ...
}: {
  programs.nh = {
    enable = true;
    flake =
      if pkgs.stdenv.isDarwin
      then "/Users/${config.user}/${mydefs.myRepoName}"
      else "/home/${config.user}/${mydefs.myRepoName}";
    clean = {
      enable = true;
      extraArgs = "--keep-since 10d --keep 3";
    };
  };
}
