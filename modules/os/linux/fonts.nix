{ pkgs, ... }:

{
  i18n.defaultLocale = "en_US.UTF-8";

  fonts = {
    fontDir.enable = true;

    packages = [
      pkgs.liberation_ttf
      pkgs.fira-code
    ];
  };
}
