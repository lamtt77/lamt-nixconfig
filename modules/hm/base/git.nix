{ inputs, config, lib, pkgs, ... }:

with lib;
let
  inherit (inputs.self) mydefs;
  cfg = config.modules.hm.base.git;
in {
  options.modules.hm.base.git = with types; {
    enable = mkEnableOption "Git Module";
  };

  config = mkIf cfg.enable {
    home.file.".globalignore".source = ../../../config/.globalignore;
    xdg.configFile."git/include".source = ../../../config/git/include;

    home = {
      packages = with pkgs; [
        tig
      ];
    };

    programs = {
      gh.enable = true;
      lazygit.enable = true;

      git = {
        enable = true;
        userName = "${mydefs.gitUserName}";
        userEmail = "${mydefs.gitUserEmail}";
        delta = {
          enable = true;
          options = {
            navigate = true;
            line-numbers = true;
            syntax-theme = "Dracula";
          };
        };
        difftastic = {
          background = "dark";
        };
        extraConfig = {
          github.user = "${mydefs.githubUser}";

          #core.fsmonitor = true; # watch FS for faster git status, using z4h instead

          credential.helper = "store";
          init.defaultBranch = "main";
          branch.autosetuprebase = "always";
          push.default = "current";
          pull.rebase = true;
          rebase = {
            autostash = true;
            autosquash = true;
          };
          commit.gpgSign = true;
          tag.gpgSign = true;
        };
        includes = [{ path = "./include"; }];
        signing.key = "${mydefs.gpgDefaultKey}";
      };
    };

  };
}
