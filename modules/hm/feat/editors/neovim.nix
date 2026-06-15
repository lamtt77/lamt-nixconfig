# Neovim module for declarative configuration
# Allows enable/disable and parameterization for reusability
{
  package ? null, # will default to pkgs.neovim inside
  extraPackages ? [ ],
  enable ? true,
}:
{
  config,
  pkgs,
  lib,
  my,
  ...
}:
with lib;
let
  neovimPackage = if package != null then package else pkgs.neovim;
  mkLink = my.mkLinkCfg config;
in
mkIf enable {
  home.packages =
    let
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
        eslint
        prettier
        typescript-language-server
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
    [ neovimPackage ]
    ++ commonDeps
    ++ lspServers
    ++ formatters
    ++ languageTools
    ++ debugTools
    ++ devEnv
    ++ extraPackages;

  xdg.configFile."nvim".source = mkLink "config/nvim";
}
