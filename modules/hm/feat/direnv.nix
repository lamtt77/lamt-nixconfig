{ config, lib, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    enableZshIntegration = true;
    enableBashIntegration = true;

    config = {
      whitelist = {
        exact = [ "$HOME/.envrc" ];
      };
    };
  };
}
