{ inputs, config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hm.base.fish;
  sources = inputs.self.nivsrc;
in {
  options.modules.hm.base.fish = with types; {
    enable = mkEnableOption "Fish shell";
  };

  config = mkIf cfg.enable {

    programs.fish = {
      enable = true;
      interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
        "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
        "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
        "source ${sources.theme-bobthefish}/functions/fish_title.fish"
        (builtins.readFile ../../../config/fish/config.fish)
        "set -g SHELL ${pkgs.fish}/bin/fish"
      ]));

      shellAbbrs = {
        ls = "eza";
        e = "emacsclient -t";
        v = "nvim";
      };

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

      plugins = map (n: {
        name = n;
        src  = sources.${n};
      }) [
        "fish-fzf"
        "fish-foreign-env"
        "theme-bobthefish"
      ];
    };
  };
}
