# From the author of Doom Emacs: https://github.com/hlissner/dotfiles/blob/master/modules/editors/emacs.nix
#
# LamT: customized for my variations
#
# with the help of options.nix module, we could avoid hard-coded username for 'config',
# and we could also comebine the reference to home-madule easily from a nixos-module itself

{ inputs, config, lib, pkgs, isWSL, ... }:

with lib;
let
  cfg = config.modules.hm.base.editors.doomemacs;
  inherit (inputs.self) mydefs;
  mkLink = config.lib.file.mkOutOfStoreSymlink
    config.home.homeDirectory + "/" + mydefs.myRepoName;
in {
  options = with types; {
    modules.hm.base.editors.doomemacs = {
      enable = mkEnableOption "Doom Emacs editor";
      doom = {
        enable = mkEnableOption "Doom Config" // {default = true;};
        repoUrl = mkOption {type = str; default = "https://github.com/doomemacs/doomemacs";};
      };
    };
  };

  config = mkIf cfg.enable {
    # only workking if inside a nixos-module or standalone, not within home-manager module
    # nixpkgs.overlays = [ inputs.emacs-overlay.overlay ];

    home.sessionPath = [
      "${config.xdg.configHome}/emacs/bin"
    ];

    home.packages = with pkgs; [
      ## Emacs itself
      binutils       # native-comp needs 'as', provided by this
      # 29.3 + native-comp
      ((emacsPackagesFor emacs-unstable).emacsWithPackages
        (epkgs: [ epkgs.vterm epkgs.pdf-tools ] ))
      # this required emacs-overlay, pureGTK is suitable for wayland-only environment
      # ((emacsPackagesFor emacsPgtkNativeComp).emacsWithPackages

      ## Doom dependencies
      git
      (ripgrep.override {withPCRE2 = true;})
      gnutls              # for TLS connectivity

      ## Optional dependencies
      fd                  # faster projectile indexing
      imagemagick         # for image-dired
      zstd                # for undo-fu-session/undo-tree compression

      ## Module dependencies
      # :checkers spell
      (aspellWithDicts (ds: with ds; [ en en-computers en-science ]))
      # :tools editorconfig
      editorconfig-core-c # per-project style config
      # :tools lookup & :lang org +roam
      sqlite
      # :lang beancount
      beancount
      # LamT: flake.nix provided unstable
      unstable.fava  # HACK Momentarily broken on nixos-unstable

      cmake
      fontconfig
      nixfmt shfmt
      shellcheck
      gnuplot
      nodePackages.bash-language-server

      ctags
      nil
      # nixd
    ] ++ (lib.optionals (!isWSL) [
      # :lang latex & :lang org (latex previews)
      texlive.combined.scheme-medium
    ]);

    # modules.shell.zsh.rcFiles = [ "${configDir}/emacs/aliases.zsh" ];
    # fonts.packages = [ pkgs.emacs-all-the-icons-fonts ];

    xdg.configFile."doom".source = mkIf cfg.doom.enable "${mkLink}/config/doom";

    # alias from home-manager.users.${username}.activation
    # home.activation is used instead of system activationScripts which has different name
    # between nix-darwin and nixos
    home.activation = mkIf cfg.doom.enable {
      installDoomEmacs = ''
        if [ ! -d "$HOME/.config/emacs" ]; then
           ${pkgs.git}/bin/git clone --depth=1 --single-branch "${cfg.doom.repoUrl}" "$HOME/.config/emacs"
        fi
      '';
    };
  };
}
