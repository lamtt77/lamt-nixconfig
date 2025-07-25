{ lib, pkgs, isWSL, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  modules.hm.base.bash.enable = true;
  modules.hm.base.zsh.enable = true;
  modules.hm.base.tmux.enable = true;
  modules.hm.base.alacritty.enable = true;
  modules.hm.base.kitty.enable = true;

  modules.hm.base.git.enable = true;
  modules.hm.base.direnv.enable = true;

  modules.hm.base.pass.enable = true;
  modules.hm.base.gnupg.enable = true;
  modules.hm.base.gnupg.enableSSHSupport = true;

  modules.hm.base.editors.doomemacs.enable = true;

  programs.ssh.enable = true;
  programs.fzf.enable = true;

  programs.go.enable = true;
  programs.helix.enable = !isWSL;
  programs.yazi.enable = true;

  home.packages = with pkgs; [
    home-manager
    nh
    niv
    cachix
    killall
    unzip

    # simple tool for making locally-trusted development certificates
    mkcert

    asciinema
    bat
    fd
    htop
    jq
    nvd
    ncdu
    ripgrep
    stow
    tldr
    tree
    watch

    ansible

    eza # Better ls
    neofetch

    nodejs
    python3
    ruby

    lf ctpv
    ranger highlight

    borgbackup
    rclone
    restic

    powershell
    p7zip

    # entertainment
    cmus
  ] ++ (lib.optionals isDarwin [
    # standard toolset
    coreutils # replace tools `du` so that `ranger` can call
    diffutils
    findutils

    gnutar

    pngpaste
  ]) ++ (lib.optionals (isLinux) [
    xclip # required for neovim
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    chromium
    firefox
    valgrind
    xfce.xfce4-terminal
    zathura

    bfg-repo-cleaner # remove large files from git history
    gopls

    # aws
    awscli2
    ssm-session-manager-plugin # Amazon SSM Session Manager Plugin
    aws-iam-authenticator
    eksctl

    # cloud tools that nix do not have cache for.
    terraform
    terraformer # generate terraform configs from existing cloud resources
    packer # machine image builder
  ]);
}
