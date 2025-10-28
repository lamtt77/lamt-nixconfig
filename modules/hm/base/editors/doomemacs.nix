# From the author of Doom Emacs: https://github.com/hlissner/dotfiles/blob/master/modules/editors/emacs.nix
# LamT: customized for my variations
{
  config,
  lib,
  my,
  pkgs,
  myargs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  cfg = config.modules.hm.base.editors.doomemacs;
  mkLink = my.mkLinkCfg config;
in
  with lib; {
    options = with types; {
      modules.hm.base.editors.doomemacs = {
        enable = mkEnableOption "Doom Emacs editor";
        doom = {
          enable =
            mkEnableOption "Doom Config"
            // {
              default = true;
            };
          repoUrl = mkOption {
            type = str;
            default = "https://github.com/doomemacs/doomemacs";
          };
        };
      };
    };

    config = mkIf cfg.enable {
      # modules.shell.zsh.rcFiles = [ "${configDir}/emacs/aliases.zsh" ];
      # fonts.packages = [
      #   (pkgs.nerdfonts.override { fonts = [ "NerdFontsSymbolsOnly" ]; })
      # ];

      xdg.configFile."doom".source = mkIf cfg.doom.enable (mkLink "config/doom");

      home = {
        # only work if inside a nixos-module or standalone, not within home-manager module
        # nixpkgs.overlays = [ inputs.emacs-overlay.overlay ];

        sessionPath = [
          "${config.xdg.configHome}/emacs/bin"
        ];

        packages = with pkgs;
          [
            # comflicted with clang/gcc
            # binutils       # native-comp needs 'as', provided by this

            # 30.5 + native-comp
            ((emacsPackagesFor emacs30).emacsWithPackages (epkgs: [
              epkgs.vterm
              epkgs.pdf-tools
            ]))
            # this required emacs-overlay, pureGTK is suitable for wayland-only environment
            # ((emacsPackagesFor emacsPgtkNativeComp).emacsWithPackages

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
              ds:
                with ds; [
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
            nodePackages.bash-language-server

            ctags
            nil
            # nixd
          ]
          ++ lib.optionals (!isDarwin) [
            gnugrep # doom-emacs vertico, support for PCRE lookaheads
          ]
          ++ lib.optionals (!myargs.wsl) [
            # :lang latex & :lang org (latex previews)
            texlive.combined.scheme-medium
          ];

        # home.activation is used instead of system activationScripts which has different name
        # between nix-darwin and nixos
        activation = mkIf cfg.doom.enable {
          installDoomEmacs = ''
            if [ ! -d "$HOME/.config/emacs" ]; then
              ${pkgs.git}/bin/git clone --depth=1 --single-branch "${cfg.doom.repoUrl}" "$HOME/.config/emacs"
            fi
          '';
        };
      };
    };
  }
