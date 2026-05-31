# zsh4humans performs much better than fish in MacOS, especially for big git repo!
{
  inputs,
  config,
  lib,
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
          swn = "sudo nixos-rebuild switch --flake ${inputs.self.outPath}";
          swh = "home-manager switch --flake ${inputs.self.outPath}";
          swb = "swn;swh";
        };
      };
    };
  }
