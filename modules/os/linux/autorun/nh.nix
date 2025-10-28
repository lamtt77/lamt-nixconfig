{
  pkgs,
  mydefs,
  myargs,
  ...
}: {
  programs.nh = {
    enable = true;
    flake =
      if pkgs.stdenv.isDarwin
      then "/Users/${myargs.username}/${mydefs.myRepoName}"
      else "/home/${myargs.username}/${mydefs.myRepoName}";
    clean = {
      enable = true;
      extraArgs = "--keep-since 10d --keep 3";
    };
  };
}
