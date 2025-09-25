# Neovim module for declarative configuration
# Allows enable/disable and parameterization for reusability
{
  config,
  lib,
  my,
  pkgs,
  ...
}: let
  cfg = config.modules.hm.base.editors.neovim;
  mkLink = my.mkLinkCfg config;
in
  with lib; {
    options = with types; {
      modules.hm.base.editors.neovim = {
        enable = mkEnableOption "Neovim editor";
        package = mkOption {
          type = package;
          default = pkgs.neovim;
          description = "Neovim package to use";
        };
        extraPackages = mkOption {
          type = listOf package;
          default = [];
          description = "Additional packages to install for Neovim";
        };
      };
    };

    config = mkIf cfg.enable {
      home.packages = with pkgs;
        [
          cfg.package
          # Common dependencies
          git
          ripgrep
          fd
          # Language servers and tools
          lua-language-server
          nil # Nix LSP
          nixd
          ctags
          # Nix formatting and linting
          statix
          alejandra
          # Add more as needed
          lua
          luarocks
          luaPackages.luacheck
          luaPackages.jsregexp
          tree-sitter
          wordnet
        ]
        ++ cfg.extraPackages;

      xdg.configFile."nvim".source = mkLink "config/nvim";
    };
  }
