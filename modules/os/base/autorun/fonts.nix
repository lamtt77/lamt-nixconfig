{ lib, pkgs, ... }:

with lib;
{
  fonts = optionalAttrs (pkgs.stdenv.isLinux) {
    fontDir.enable = true;

    packages = [
      pkgs.liberation_ttf
      pkgs.fira-code
    ];
  } // optionalAttrs (pkgs.stdenv.isDarwin) {
    packages = with pkgs; [
      # icon fonts
      material-design-icons
      font-awesome

      nerd-fonts.symbols-only
      # nerd-fonts.fira-code
      # nerd-fonts.jetbrains-mono
      # nerd-fonts.iosevka

      dejavu_fonts
    ];
  };
}
