{
  config,
  pkgs,
  mydefs,
  myargs,
  ...
}: {
  config = let
    inherit (mydefs) stateVersion;
    inherit (pkgs.stdenv) isDarwin;
  in {
    home = {
      inherit stateVersion;
      username = myargs.username;
      homeDirectory =
        if isDarwin
        then "/Users/${myargs.username}"
        else "/home/${myargs.username}";
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
