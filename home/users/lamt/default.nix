{ lib, pkgs, isWSL, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  modules.hm.base.bash.enable = true;
  modules.hm.base.zsh.enable = true;
  modules.hm.base.fish.enable = true;
  modules.hm.base.tmux.enable = true;
  modules.hm.base.alacritty.enable = true;
  modules.hm.base.kitty.enable = true;

  modules.hm.base.git.enable = true;
  modules.hm.base.direnv.enable = true;

  modules.hm.base.pass.enable = true;
  modules.hm.base.gnupg.enable = true;
  modules.hm.base.gnupg.gpg-agent.enable = true;


  modules.hm.base.editors.doomemacs.enable = true;
  modules.hm.base.editors.neovim.enable = true;

  programs.fzf.enable = true;

  programs.go.enable = true;
  programs.helix.enable = !isWSL;
  programs.yazi.enable = true;

  home.packages = with pkgs; [
    home-manager
    niv
    cachix

    asciinema
    bat
    fd
    gh
    htop
    jq
    nvd
    unstable.ncdu               # https://github.com/NixOS/nixpkgs/issues/290512
    ripgrep
    stow
    tldr
    tree
    watch

    tree-sitter                 # only needed for nvim :TSInstallFromGrammar

    ansible
    delta # for highlight git
    eza # Better ls

    gopls

    nodejs # required for Copilot.vim
    zigpkgs.master
    python3
    ruby

    lf ctpv
    ranger highlight

    borgbackup
    rclone
    restic

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
    tailscale # this is automatically setup on Linux
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    chromium
    firefox
    valgrind
    xfce.xfce4-terminal
    zathura
  ]);
}
