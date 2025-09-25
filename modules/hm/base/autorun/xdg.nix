{
  config,
  lib,
  my,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv) isLinux;
  mkLink = my.mkLinkCfg config;
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

  home.file = {
    ".vimrc".source = mkLink "config/.vimrc";
    ".gdbinit".source = mkLink "config/.gdbinit";
    ".inputrc".source = mkLink "config/.inputrc";
  };

  xdg.configFile =
    {
      "ranger".source = mkLink "config/ranger";
    }
    // lib.optionalAttrs isDarwin {
      "karabiner".source = mkLink "config/karabiner";
      # Rectangle.app. This has to be imported manually using the app itself.
      "rectangle".source = mkLink "config/_darwin/rectangle";
    }
    // lib.optionalAttrs isLinux {
      "ghostty".source = mkLink "config/_linux/ghostty";
    };
}
