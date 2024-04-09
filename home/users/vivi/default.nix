{ lib, pkgs, isWSL, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  modules.hm.base.kitty.enable = true;

  home.packages = with pkgs; [
    asciinema
    bat
    fd
    fzf
    htop
    jq
    ripgrep
    tldr
    tree
    watch
    xz

    nodejs
    python3
    ruby

    ranger

    # entertainment
    cmus
  ] ++ (lib.optionals isDarwin [
    # standard toolset
    coreutils # replace tools `du` so that `ranger` can call
    diffutils
    findutils

    gnugrep # doom-emacs vertico, support for PCRE lookaheads
    gnupg
    pinentry_mac
    pngpaste
   # This is automatically setup on Linux
    cachix
    # XQuartz and X11
    xquartz
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    chromium
    rofi
    xfce.xfce4-terminal
    zathura
  ]);

  programs.zsh = {
    enable = true;
    # zsh4humans performs much better than fish in MacOS, especially for big git repo!
    # default shell for MacOS: z4h, NixOS: fish
    initExtra = builtins.readFile ../../../config/.z4hrc;
    envExtra = builtins.readFile ../../../config/.z4henv;
  };

 programs.fzf.enable = true;

  programs.go = {
    enable = true;
  };

}
