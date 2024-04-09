{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hm.base.kitty;
in {
  options.modules.hm.base.kitty = with types; {
    enable = mkEnableOption "Kitty module";
  };

  config = mkIf cfg.enable {
    programs.kitty = {
      enable = true;
      font = {
        name =
          if pkgs.stdenv.isDarwin
          then "Monaco Nerd Font"
          else "Liberation Mono";
        size =
          if pkgs.stdenv.isDarwin
          then 15.5
          else 11;
      };

      # macOS specific settings
      darwinLaunchOptions = ["--start-as=maximized"];

      extraConfig = builtins.readFile ../../../config/kitty/kitty.conf;
    };
  };
}
