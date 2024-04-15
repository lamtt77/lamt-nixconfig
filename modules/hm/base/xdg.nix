{ inputs, config, lib, pkgs, ... }:

let
  inherit (inputs) self;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # We must use an absolute path here to get out of store symlink working
  # However getEnv "HOME" does not work||!
  # Is there anyway to prevent the harded-code myRepoName?
  #
  # Caveat:
  #   Out of store symlink will not be included in WSL tarballBuilder
  #   So you have to run nixos-rebuild switch one more time after imported WSL tarball
  mkLink = config.lib.file.mkOutOfStoreSymlink
    config.home.homeDirectory + "/" + self.mydefs.myRepoName;
in {
  xdg.enable = true;

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    # MANPAGER = "${manpager}/bin/manpager";
  };

  # just to demo the usage of inputs.self, can't use vim->gf to go to the file directly with this'
  home.file.".gdbinit".source = "${self}/config/.gdbinit";

  home.file.".inputrc".source = ../../../config/.inputrc;
  home.file.".globalignore".source = ../../../config/.globalignore;

  xresources.extraConfig = builtins.readFile ../../../config/.Xresources;

  xdg.configFile = {
    "lf".source = "${mkLink}/config/lf";
    "ranger".source = "${mkLink}/config/ranger";
  } // lib.optionalAttrs isDarwin {
    "karabiner".source = ../../../config/karabiner;
    # Rectangle.app. This has to be imported manually using the app itself.
    "rectangle".source = ../../../config/_darwin/rectangle;
  } // lib.optionalAttrs isLinux {
    "ghostty".source = ../../../config/_linux/ghostty;
  };
}
