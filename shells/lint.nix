{pkgs, ...}:
pkgs.mkShellNoCC {
  nativeBuildInputs = with pkgs; [
    actionlint
    luaPackages.luacheck
    stylua
    statix
    alejandra
    yamllint
  ];
}
