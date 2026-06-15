# From the author of Doom Emacs: https://github.com/hlissner/dotfiles/blob/master/modules/editors/emacs.nix
# LamT: customized for my variations
{
  doomEnable ? true,
  doomRepoUrl ? "https://github.com/doomemacs/doomemacs",
}:
{
  config,
  lib,
  my,
  pkgs,
  myargs,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
  mkLink = my.mkLinkCfg config;
in
{
  xdg.configFile."doom".source = lib.mkIf doomEnable (mkLink "config/doom");

  home = {
    sessionPath = [
      "${config.xdg.configHome}/emacs/bin"
    ];

    packages =
      with pkgs;
      [
        ((emacsPackagesFor emacs30).emacsWithPackages (epkgs: [
          epkgs.vterm
          epkgs.pdf-tools
        ]))

        ## Doom dependencies
        git
        ripgrep
        gnutls # for TLS connectivity

        ## Optional dependencies
        fd # faster projectile indexing
        imagemagick # for image-dired
        zstd # for undo-fu-session/undo-tree compression

        ## Module dependencies
        # :checkers spell
        (aspellWithDicts (
          ds: with ds; [
            en
            en-computers
            en-science
          ]
        ))
        # :tools editorconfig
        editorconfig-core-c # per-project style config
        # :tools lookup & :lang org +roam
        sqlite
        # :lang beancount
        beancount
        fava

        cmake
        fontconfig
        shfmt
        shellcheck
        gnuplot
        bash-language-server

        ctags
        nil
      ]
      ++ lib.optionals (!isDarwin) [
        gnugrep # doom-emacs vertico, support for PCRE lookaheads
      ]
      ++ lib.optionals (!myargs.wsl) [
        # :lang latex & :lang org (latex previews)
        texlive.combined.scheme-medium
      ];

    activation = lib.mkIf doomEnable {
      installDoomEmacs = ''
        if [ ! -d "$HOME/.config/emacs" ]; then
          ${pkgs.git}/bin/git clone --depth=1 --single-branch "${doomRepoUrl}" "$HOME/.config/emacs"
        fi
      '';
    };
  };
}
