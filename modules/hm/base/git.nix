{
  inputs,
  config,
  lib,
  my,
  pkgs,
  mydefs,
  ...
}:
let
  cfg = config.modules.hm.base.git;
  mkLink = my.mkLinkCfg config;
  inherit (inputs) self;
in
with lib;
{
  options.modules.hm.base.git = with types; {
    enable = mkEnableOption "Git Module";
  };

  config = mkIf cfg.enable {
    home = {
      activation.installRepoGitHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Install pre-commit hook in the repo if it exists
        REPO_PATH="$HOME/${mydefs.myRepoName}"
        if [ -d "$REPO_PATH/.git/hooks" ]; then
          rm -f "$REPO_PATH/.git/hooks/pre-commit"
          cp ${self}/config/git/hooks/pre-commit "$REPO_PATH/.git/hooks/pre-commit"
          chmod +x "$REPO_PATH/.git/hooks/pre-commit"
        fi
      '';

      file = {
        ".globalignore".source = mkLink "config/.globalignore";
      };

      packages = with pkgs; [
        tig
      ];
    };

    xdg.configFile."git/include".source = mkLink "config/git/include";
    xdg.configFile."tig/config".text = ''
      set line-graphics = utf-8
      set tab-size = 4
      set diff-highlight = ${pkgs.git}/share/git/contrib/diff-highlight/diff-highlight

      color cursor 15 blue
      set main-view = date:relative id:yes author:full commit-title:yes,graph,refs,overflow=no
    '';

    programs = {
      gh.enable = true;
      lazygit.enable = true;

      git = {
        enable = true;
        settings = {
          user = {
            name = "${mydefs.gitUserName}";
            email = "${mydefs.gitUserEmail}";
          };
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
        includes = [ { path = "./include"; } ];
        signing.key = "${mydefs.gpgDefaultKey}";
      };

      delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          navigate = true;
          line-numbers = true;
          syntax-theme = "Dracula";
        };
      };

      difftastic = {
        enable = true;
        options.background = "dark";
      };
    };
  };
}
