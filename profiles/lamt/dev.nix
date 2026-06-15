{
  pkgs,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    cargo
    clippy
    rustc
    rustfmt
    nixfmt
    zig
    nodejs
    clang-tools
    (python3.withPackages (
      ps: with ps; [
        pip
        pynvim
        python-lsp-ruff
        python-lsp-server
        debugpy
      ]
    ))
    vscode-js-debug
    hyperfine
  ];
}
