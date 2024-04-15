{ inputs, config, lib, pkgs, isWSL, ... }:

with lib;
let
  inherit (inputs) self;
  sources = self.nivsrc;
  cfg = config.modules.hm.base.editors.neovim;
in {
  options = with types; {
    modules.hm.base.editors.neovim = {
      enable = mkEnableOption "Neovim editor";
    };
  };

  config = mkIf cfg.enable {
    xdg.configFile = {
      "nvim/parser/proto.so".source = "${pkgs.tree-sitter-proto}/parser";
      "nvim/queries/proto/folds.scm".source = "${sources.tree-sitter-proto}/queries/folds.scm";
      "nvim/queries/proto/highlights.scm".source = "${sources.tree-sitter-proto}/queries/highlights.scm";
      "nvim/queries/proto/textobjects.scm".source = "${self}/config/textobjects.scm";
    };

    programs.neovim = {
      enable = true;
      package = pkgs.neovim-nightly;
      withPython3 = true;

      extraConfig = (import ./_vim-config.nix) {inherit sources;};

      plugins = with pkgs; [
        customVim.vim-copilot
        customVim.vim-cue
        customVim.vim-fish
        customVim.vim-fugitive
        customVim.vim-glsl
        customVim.vim-misc
        customVim.vim-pgsql
        customVim.vim-tla
        customVim.vim-zig
        customVim.pigeon
        customVim.AfterColors

        customVim.vim-nord
        customVim.nvim-comment
        customVim.nvim-conform
        customVim.nvim-lspconfig
        customVim.nvim-plenary # required for telescope
        customVim.nvim-telescope
        customVim.nvim-treesitter
        customVim.nvim-treesitter-playground
        customVim.nvim-treesitter-textobjects

        vimPlugins.vim-airline
        vimPlugins.vim-airline-themes
        vimPlugins.vim-eunuch
        vimPlugins.vim-gitgutter

        vimPlugins.vim-markdown
        vimPlugins.vim-nix
        vimPlugins.typescript-vim
        vimPlugins.nvim-treesitter-parsers.elixir
      ] ++ lib.optionals (!isWSL) [
        # This is causing a segfaulting while building our installer for WSL
        customVim.vim-devicons
      ];
    };
  };
}
