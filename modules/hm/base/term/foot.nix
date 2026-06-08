{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.hm.base.term.foot;
in
{
  options.modules.hm.base.term.foot = with types; {
    enable = mkEnableOption "Foot shell";
  };

  config = mkIf cfg.enable {
    programs.foot = {
      enable = true;
      settings = {
        main.font = "Liberation Mono:size=13";
        scrollback.lines = 100000;
      };
    };

    home.packages = with pkgs; [
      libsixel # image support in foot
    ];
  };
}
