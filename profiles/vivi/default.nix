{ lib, pkgs, isWSL, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  modules.hm.base.bash.enable = true;
  modules.hm.base.zsh.enable = true;
  modules.hm.base.kitty.enable = true;

  programs.fzf.enable = true;

  home.packages = with pkgs; [
    asciinema
    bat
    fd
    htop
    jq
    ripgrep
    tldr
    tree
    watch

    nodejs
    python3

    ranger
  ] ++ (lib.optionals isDarwin [
    # standard toolset
    coreutils # replace tools `du` so that `ranger` can call
    diffutils
    findutils
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    chromium
    xfce.xfce4-terminal
  ]);

}
