{ pkgs, ... }:
pkgs.mkShellNoCC {
  nativeBuildInputs = with pkgs; [
    actionlint
    luaPackages.luacheck
    stylua
    statix
    nixfmt
    yamllint
    cargo
    clippy
    rustc
    rustfmt
  ];
}
