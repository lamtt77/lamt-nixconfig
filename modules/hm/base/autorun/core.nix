{
  config,
  pkgs,
  mydefs,
  ...
}: {
  config = let
    inherit (mydefs) stateVersion;
    inherit (pkgs.stdenv) isDarwin;
  in {
    home = {
      inherit stateVersion;
      username = config.user;
      homeDirectory =
        if isDarwin
        then "/Users/${config.user}"
        else "/home/${config.user}";
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
