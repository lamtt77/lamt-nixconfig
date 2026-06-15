# Yazi file manager module
{
  config,
  lib,
  my,
  pkgs,
  ...
}:
let
  mkLink = my.mkLinkCfg config;
in
{
  programs.yazi = {
    enable = true;
    package = pkgs.yazi;
    shellWrapperName = "y";
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  xdg.configFile."yazi".source = mkLink "config/yazi";
}
