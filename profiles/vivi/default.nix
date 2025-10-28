{
  lib,
  pkgs,
  myargs,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  modules.hm.base.bash.enable = true;
  modules.hm.base.zsh.enable = true;
  modules.hm.base.term.kitty.enable = true;

  programs.fzf.enable = true;

  home.packages = with pkgs;
    [
      asciinema
      bat
      fd
      htop
      jq
      nh
      tldr
      tree
      watch

      nodejs

      ranger
    ]
    ++ (lib.optionals isDarwin [
      # standard toolset
      coreutils # replace tools `du` so that `ranger` can call
      diffutils
      findutils
    ])
    ++ (lib.optionals (isLinux && !myargs.wsl) [
      chromium
      xfce.xfce4-terminal
    ]);
}
