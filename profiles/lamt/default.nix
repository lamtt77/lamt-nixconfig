{
  lib,
  pkgs,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv) isLinux;
in {
  modules.hm.base.bash.enable = true;
  modules.hm.base.zsh.enable = true;
  # programs.nushell.enable = true;

  modules.hm.base.term.tmux.enable = true;
  modules.hm.base.term.zellij.enable = true;
  modules.hm.base.term.alacritty.enable = true;
  modules.hm.base.term.kitty.enable = true;
  modules.hm.base.term.foot.enable = isLinux;

  modules.hm.base.git.enable = true;
  modules.hm.base.direnv.enable = true;

  modules.hm.base.pass.enable = true;
  modules.hm.base.gnupg.enable = true;
  modules.hm.base.gnupg.enableSSHSupport = true;

  modules.hm.base.yt-dlp.enable = true;
  modules.hm.base.firefox.enable = !isDarwin;

  modules.hm.base.editors.doomemacs.enable = true;
  modules.hm.base.editors.helix.enable = true;
  modules.hm.base.editors.vscode.enable = true;
  modules.hm.base.editors.neovim.enable = true;
  modules.hm.base.tools.yazi.enable = true;
  # modules.hm.base.editors.zed.enable = true;

  modules.hm.base.lang.cc.enable = isLinux;

  programs.ssh.enable = true;
  programs.fzf.enable = true;
  programs.man.enable = true;

  programs.go.enable = true;
  programs.yazi.enable = true;

  home.packages = with pkgs;
    [
      nh
      cachix
      killall
      unzip
      chezmoi
      nix-prefetch-git

      # AI
      helix-gpt

      (python3.withPackages (ps:
        with ps; [
          pip

          # Helix Python LSP requirements
          python-lsp-ruff
          python-lsp-server
        ]))

      ookla-speedtest

      imagemagick
      ffmpeg
      cargo
      zig

      docker-compose

      # simple tool for making locally-trusted development certificates
      mkcert

      asciinema
      bat
      htop
      iperf
      jq
      lsof
      ncdu
      nvd
      stow
      tldr
      tree
      watch
      ansible

      eza # Better ls
      neofetch

      nodejs
      ranger
      highlight

      borgbackup
      rclone
      restic

      ipmitool

      powershell
      p7zip

      # entertainment
      cmus
    ]
    ++ (lib.optionals isDarwin [
      # standard toolset
      coreutils # replace tools `du` so that `ranger` can call
      diffutils
      findutils

      gnutar

      pngpaste
    ])
    ++ (lib.optionals isLinux [
      # AI
      unstable.opencode

      xclip
      maim
      flameshot
    ])
    ++ (lib.optionals (isLinux && !isWSL) [
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
