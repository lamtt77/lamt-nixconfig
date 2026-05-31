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
          default = pkgs.unstable.neovim;
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
      home.packages = let
        commonDeps = with pkgs; [
          git
          ripgrep
          fd
          ctags
        ];

        lspServers = with pkgs; [
          lua-language-server
          nil # Nix LSP
          nixd
        ];

        formatters = with pkgs; [
          statix
          alejandra
          stylua
        ];

        languageTools = with pkgs; [
          # Go
          gopls
          # Python
          ruff
          pyright
          # JavaScript/TypeScript
          nodePackages.eslint
          nodePackages.prettier
          nodePackages.typescript-language-server
          # C/C++
          clang-tools # clangd, clang-format
          cppcheck
          # Rust
          rust-analyzer
        ];

        debugTools = with pkgs; [
          delve
          lldb
          codelldb
        ];

        devEnv = with pkgs; [
          devenv
          lua
          luarocks
          luaPackages.luacheck
          luaPackages.jsregexp
          tree-sitter
          wordnet
        ];
      in
        [cfg.package]
        ++ commonDeps
        ++ lspServers
        ++ formatters
        ++ languageTools
        ++ debugTools
        ++ devEnv
        ++ cfg.extraPackages;

      xdg.configFile."nvim".source = mkLink "config/nvim";
    };
  }
