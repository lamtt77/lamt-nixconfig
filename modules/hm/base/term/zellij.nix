{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.hm.base.term.zellij;
in
{
  options.modules.hm.base.term.zellij = with types; {
    enable = mkEnableOption "Zellij Terminal Multiplexers";
  };

  config = mkIf cfg.enable {
    programs.zellij = {
      enable = true;
      settings = {
        theme = "catppuccin-macchiato";
      };
    };
  };
}
