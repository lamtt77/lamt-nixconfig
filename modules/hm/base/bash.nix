{ config, lib, ... }:

with lib;
let
  cfg = config.modules.hm.base.bash;
in {
  options.modules.hm.base.bash = with types; {
    enable = mkEnableOption "Bash shell";
  };

  config = mkIf cfg.enable {
    programs.bash = {
      enable = true;
      shellOptions = [];
      historyControl = [ "ignoredups" "ignorespace" ];
      initExtra = builtins.readFile ../../../config/.bashrc;

      shellAliases = {
        ga = "git add";
        gc = "git commit";
        gco = "git checkout";
        gcp = "git cherry-pick";
        gdiff = "git diff";
        gl = "git prettylog";
        gp = "git push";
        gs = "git status";
        gt = "git tag";
      };
    };
  };
}
