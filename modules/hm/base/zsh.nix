# zsh4humans performs much better than fish in MacOS, especially for big git repo!

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hm.base.zsh;
in {
  options.modules.hm.base.zsh = with types; {
    enable = mkEnableOption "Zsh shell";
  };

  config = mkIf cfg.enable {
    home.file.".p10k.zsh".source = ../../../config/.p10k.zsh;

    programs.zsh = {
      enable = true;
      initExtra = builtins.readFile ../../../config/.z4hrc;
      envExtra = builtins.readFile ../../../config/.z4henv;
    };
  };
}
