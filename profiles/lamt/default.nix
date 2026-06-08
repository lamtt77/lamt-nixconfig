{
  lib,
  pkgs,
  myargs,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv) isLinux;
in
{
  modules = {
    hm = {
      base = {
        bash.enable = true;
        zsh.enable = true;
        # programs.nushell.enable = true;

        term = {
          tmux.enable = true;
          zellij.enable = true;
          alacritty.enable = true;
          kitty.enable = true;
          ghostty.enable = !isDarwin;
          foot.enable = isLinux;
        };

        git.enable = true;
        direnv.enable = true;

        pass.enable = true;
        gnupg.enable = true;
        gnupg.enableSSHSupport = true;

        yt-dlp.enable = true;
        firefox.enable = !isDarwin && (myargs.hostname != "air15vm");

        editors = {
          doomemacs.enable = myargs.hostname == "macair15-m2";
          helix.enable = true;
          vscode.enable = true;
          neovim.enable = true;
        };
        tools.yazi.enable = true;
        # editors.zed.enable = true;

        lang.cc.enable = isLinux;
      };
    };
  };

  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;
    };
    fzf.enable = true;
    man.enable = true;

    go.enable = true;
    yazi.enable = true;
  };

  home.packages =
    let
      # Common packages for all platforms
      commonPackages = with pkgs; [
        cachix
        hugo
        killall
        unzip
        chezmoi
        nix-prefetch-git
        ookla-speedtest
        imagemagick
        librsvg # SVG rendering support for imagemagick/image.nvim
        ffmpeg
        docker-compose
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
        fastfetch
        ranger
        highlight
        borgbackup
        rclone
        restic
        ipmitool
        powershell
        p7zip
        cmus

        # DigitalOcean
        doctl
      ];

      # Programming languages
      languages = with pkgs; [
        cargo
        clippy
        rustc
        rustfmt
        nixfmt
        zig
        nodejs
        clang-tools # C/C++ LSP and tools
        (python3.withPackages (
          ps: with ps; [
            pip
            pynvim
            python-lsp-ruff
            python-lsp-server
            debugpy
          ]
        ))
      ];

      # Debugging tools
      debugging = with pkgs; [
        vscode-js-debug # JavaScript/TypeScript debugging adapter
        hyperfine
      ];

      # Linux AI tools
      linuxAi = with pkgs; [
        opencode
        gemini-cli
      ];

      # macOS-specific packages
      darwinPackages = with pkgs; [
        coreutils # replace tools `du` so that `ranger` can call
        diffutils
        findutils
        gnutar
        pngpaste
      ];

      # Linux-specific packages
      linuxPackages = with pkgs; [
        xclip
        maim
        flameshot
      ];

      # Linux non-WSL specific packages
      linuxNonWslPackages = with pkgs; [
        chromium
        firefox
        valgrind
        xfce4-terminal
        zathura
        awscli2
        ssm-session-manager-plugin # Amazon SSM Session Manager Plugin
        aws-iam-authenticator
        eksctl
        # terraform
        # terraformer # generate terraform configs from existing cloud resources
        # packer # machine image builder
      ];
    in
    commonPackages
    ++ languages
    ++ debugging
    ++ (lib.optionals isDarwin darwinPackages)
    ++ (lib.optionals isLinux linuxPackages)
    ++ (lib.optionals isLinux linuxAi)
    ++ (lib.optionals (isLinux && !myargs.wsl) linuxNonWslPackages);
}
