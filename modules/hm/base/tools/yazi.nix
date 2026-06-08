# Yazi file manager module
{
  config,
  lib,
  my,
  pkgs,
  ...
}:
let
  cfg = config.modules.hm.base.tools.yazi;
  mkLink = my.mkLinkCfg config;
in
with lib;
{
  options.modules.hm.base.tools.yazi = {
    enable = mkEnableOption "Yazi file manager" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    programs.yazi = {
      enable = true;
      package = pkgs.yazi;
      shellWrapperName = "y";
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    xdg.configFile."yazi".source = mkLink "config/yazi";
  };
}
