# zsh4humans performs much better than fish in MacOS, especially for big git repo!
{
  inputs,
  config,
  lib,
  my,
  pkgs,
  ...
}: let
  cfg = config.modules.hm.base.zsh;
  inherit (inputs) self;
in
  with lib; {
    options.modules.hm.base.zsh = with types; {
      enable = mkEnableOption "Zsh shell";
    };

    config = mkIf cfg.enable {
      home.file.".p10k.zsh".source = "${self}/config/zsh/.p10k.zsh";

      programs.zsh = {
        enable = true;
        initContent = builtins.readFile "${self}/config/zsh/.z4hrc";
        envExtra = builtins.readFile "${self}/config/zsh/.z4henv";

        shellAliases = {
          nh-clean = "nh clean all --keep-since 10d --keep 3";
          swn = "nh os switch ${inputs.self.outPath}";
          swh = "nh home switch ${inputs.self.outPath}";
          swb = "swn;swh";
        };
      };
    };
  }
