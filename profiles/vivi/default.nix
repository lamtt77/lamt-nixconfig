{
  lib,
  pkgs,
  my,
  myargs,
  ...
}:
let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  profileFeatures = [
    ../../modules/hm/feat/bash.nix
    ../../modules/hm/feat/zsh.nix
    ../../modules/hm/feat/term/kitty.nix
  ];
in
{
  imports = my.resolveFeatures profileFeatures;

  programs.fzf.enable = true;

  home.packages =
    with pkgs;
    [
      asciinema
      bat
      fd
      htop
      jq
      tldr
      tree
      watch

      nodejs

      yazi
    ]
    ++ (lib.optionals isDarwin [
      # standard toolset
      coreutils # replace tools `du` so that `ranger` can call
      diffutils
      findutils
    ])
    ++ (lib.optionals (isLinux && !myargs.wsl) [
      chromium
      xfce4-terminal
    ]);
}
