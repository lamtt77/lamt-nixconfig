{ pkgs, ... }:

{
  fonts = {
    fontDir.enable = true;

    packages = [
      pkgs.liberation_ttf
      pkgs.fira-code
    ];
  };
}
