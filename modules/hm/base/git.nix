{ config, lib, ... }:

with lib;
let cfg = config.modules.hm.base.git;
in {
  options.modules.hm.base.git = with types; {
    enable = mkEnableOption "Git Conf";
  };

  config = mkIf cfg.enable {
    xdg.configFile."git".source = ../../../config/git;
    home.file.".globalignore".source = ../../../config/.globalignore;
  };
}
