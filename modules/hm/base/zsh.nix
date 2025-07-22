# zsh4humans performs much better than fish in MacOS, especially for big git repo!

{ inputs, config, lib, pkgs, username, ... }:

with lib;
let
  cfg = config.modules.hm.base.zsh;
  inherit (inputs.self) mydefs;
  flakeHome = if pkgs.stdenv.isDarwin
              then "/Users/${username}/${mydefs.myRepoName}"
              else "/home/${username}/${mydefs.myRepoName}";
in {
  options.modules.hm.base.zsh = with types; {
    enable = mkEnableOption "Zsh shell";
  };

  config = mkIf cfg.enable {
    home.file.".p10k.zsh".source = ../../../config/.p10k.zsh;

    programs.zsh = {
      enable = true;
      initContent = builtins.readFile ../../../config/.z4hrc;
      envExtra = builtins.readFile ../../../config/.z4henv;

      shellAliases = {
        speedtest = "curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python -";

        nh-clean = "nh clean all --keep-since 14d --keep 5";
        swn = "nh os switch ${flakeHome}";
        swh = "nh home switch ${flakeHome}";
        swb = "swn;swh";
      };
    };
  };
}
