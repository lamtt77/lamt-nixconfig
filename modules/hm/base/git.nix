{
  inputs,
  config,
  lib,
  my,
  pkgs,
  mydefs,
  ...
}: let
  cfg = config.modules.hm.base.git;
  mkLink = my.mkLinkCfg config;
in
  with lib; {
    options.modules.hm.base.git = with types; {
      enable = mkEnableOption "Git Module";
    };

    config = mkIf cfg.enable {
      home.file.".globalignore".source = mkLink "config/.globalignore";

      xdg.configFile."git/include".source = mkLink "config/git/include";
      xdg.configFile."tig/config".text = ''
        set line-graphics = utf-8
        set tab-size = 4
        set diff-highlight = ${pkgs.git}/share/git/contrib/diff-highlight/diff-highlight

        color cursor 15 blue
        set main-view = date:relative id:yes author:full commit-title:yes,graph,refs,overflow=no
      '';

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
          includes = [{path = "./include";}];
          signing.key = "${mydefs.gpgDefaultKey}";
        };
      };
    };
  }
