{
  pkgs,
  lib,
  myargs,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv) isLinux;
in
{
  home.packages =
    with pkgs;
    [
      cachix
      hugo
      killall
      unzip
      chezmoi
      nix-prefetch-git
      ookla-speedtest
      imagemagick
      librsvg
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
      eza
      fastfetch
      ranger
      highlight
      ipmitool
      powershell
      p7zip
      cmus
      opencode
    ]
    ++ lib.optionals isDarwin [
      coreutils
      diffutils
      findutils
      gnutar
      pngpaste
    ]
    ++ lib.optionals isLinux [
      xclip
      maim
      flameshot
      gemini-cli
    ]
    ++ lib.optionals (isLinux && !myargs.wsl) [
      chromium
      valgrind
      xfce4-terminal
      zathura
    ];
}
