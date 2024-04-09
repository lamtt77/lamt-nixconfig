{ inputs, config, pkgs, ... }:

let
  inherit (inputs) self;
  sources = inputs.self.nivsrc;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  outstorecfg = config.lib.file.mkOutOfStoreSymlink
    config.home.homeDirectory + "/" + self.mydefs.myRepoName + "/config";
in {
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
  home.file.".p10k.zsh".source = ../../../config/.p10k.zsh;

  xresources.extraConfig = builtins.readFile ../../../config/.Xresources;

  xdg.configFile = {
    "git".source = ../../../config/git;
    "lf".source = "${outstorecfg}/lf";
    "ranger".source = "${outstorecfg}/ranger";
    "karabiner".source = ../../../config/karabiner;

    # tree-sitter parsers
    "nvim/parser/proto.so".source = "${pkgs.tree-sitter-proto}/parser";
    "nvim/queries/proto/folds.scm".source = "${sources.tree-sitter-proto}/queries/folds.scm";
    "nvim/queries/proto/highlights.scm".source = "${sources.tree-sitter-proto}/queries/highlights.scm";
    "nvim/queries/proto/textobjects.scm".source = ../../../config/textobjects.scm;
  } // (if isDarwin then {
    # Rectangle.app. This has to be imported manually using the app.
    "rectangle".source = ../../../config/_darwin/rectangle;
  } else if isLinux then {
    "i3".source = ../../../config/_linux/i3;
    "rofi".source = ../../../config/_linux/rofi;
    "sway".source = ../../../config/_linux/sway;
    # "sway/custom.conf".source = "${outstorecfg}/sway/custom.conf";
    "hypr/custom.conf".source = "${outstorecfg}/hypr/custom.conf";
    "ghostty".source = ../../../config/_linux/ghostty;
  } else {});
}
