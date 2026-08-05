# zsh4humans performs much better than fish in MacOS, especially for big git repo!
{
  inputs,
  config,
  lib,
  ...
}:
{
  home.sessionPath = [ "${config.home.homeDirectory}/.npm-global/bin" ];

  home.file = {
    ".p10k.zsh".source = ../../../config/zsh/.p10k.zsh;
  };

  programs.zsh = {
    enable = true;
    # dotDir = "${config.xdg.configHome}/zsh";
    dotDir = config.home.homeDirectory;

    initContent = builtins.readFile ../../../config/zsh/.z4hrc;
    envExtra = builtins.readFile ../../../config/zsh/.z4henv;

    shellAliases = { };
  };
}
