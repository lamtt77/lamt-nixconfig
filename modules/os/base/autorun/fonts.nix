{
  lib,
  pkgs,
  ...
}:
with lib;
{
  fonts =
    optionalAttrs (pkgs.stdenv.isLinux) {
      fontDir.enable = true;

      packages = with pkgs; [
        fira-code
        fira-code-symbols
        liberation_ttf_v2
        noto-fonts

        font-awesome
        nerd-fonts.symbols-only
      ];
    }
    // optionalAttrs (pkgs.stdenv.isDarwin) {
      packages = with pkgs; [
        dejavu_fonts

        material-design-icons

        font-awesome
        nerd-fonts.symbols-only
        # nerd-fonts.fira-code
        # nerd-fonts.jetbrains-mono
        # nerd-fonts.iosevka
      ];
    };
}
