{ lib, pkgs, isWSL, ... }:

let
  sources = import ../../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  modules.hm.base.gnupg.enable = true;
  modules.hm.base.kitty.enable = true;

  modules.hm.base.editors.doomemacs.enable = true;
  modules.hm.base.editors.neovim.enable = true;

  programs.helix.enable = !isWSL;
  programs.yazi.enable = true;

  home.packages = with pkgs; [
    asciinema
    bat
    fd
    fzf
    gh
    htop
    jq
    nvd
    pass
    unstable.ncdu               # https://github.com/NixOS/nixpkgs/issues/290512
    ripgrep
    stow
    tldr
    tree
    watch
    xz

    tree-sitter                 # only needed for nvim :TSInstallFromGrammar

    ansible
    delta # for highlight git
    eza # Better ls

    gopls
    zigpkgs.master

    # Node is required for Copilot.vim
    nodejs

    python3
    ruby

    lf
    ctpv
    ranger

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
   # This is automatically setup on Linux
    cachix
    tailscale
    # XQuartz and X11
    xquartz
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    chromium
    firefox
    rofi
    valgrind
    xfce.xfce4-terminal
    zathura
  ]) ++ (lib.optionals (isLinux) [
    pinentry
  ]);

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ../../../config/.bashrc;

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
    };
  };

  programs.zsh = {
    enable = true;
    # zsh4humans performs much better than fish in MacOS, especially for big git repo!
    # default shell for MacOS: z4h, NixOS: fish
    initExtra = builtins.readFile ../../../config/.z4hrc;
    envExtra = builtins.readFile ../../../config/.z4henv;
  };

  programs.direnv = {
    enable = true;

    config = {
      whitelist = {
        exact = ["$HOME/.envrc"];
      };
    };
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_title.fish"
      (builtins.readFile ../../../config/fish/config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
    ]));

    shellAbbrs = {
      ls = "eza";
      e = "emacsclient -t";
      v = "nvim";
    };

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
    };

    plugins = map (n: {
      name = n;
      src  = sources.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };

  programs.fzf.enable = true;

  programs.go = {
    enable = true;
  };

  programs.tmux = {
    enable = true;
    terminal = "xterm-256color";
    shortcut = "l";
    secureSocket = false;

    extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"

      set -g @dracula-show-battery false
      set -g @dracula-show-network false
      set -g @dracula-show-weather false

      bind -n C-k send-keys "clear"\; send-keys "Enter"

      run-shell ${sources.tmux-pain-control}/pain_control.tmux
      run-shell ${sources.tmux-dracula}/dracula.tmux
    '';
  };

  programs.alacritty = {
    enable = !isWSL;

    settings = {
      env.TERM = "xterm-256color";

      key_bindings = [
        { key = "K"; mods = "Command"; chars = "ClearHistory"; }
        { key = "V"; mods = "Command"; action = "Paste"; }
        { key = "C"; mods = "Command"; action = "Copy"; }
        { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
        { key = "Equals"; mods = "Command"; action = "IncreaseFontSize"; }
        { key = "Minus"; mods = "Command"; action = "DecreaseFontSize"; }
      ];
    };
  };

}
