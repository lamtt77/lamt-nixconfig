{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.foot = {
    enable = true;
    settings = {
      main.font = "Liberation Mono:size=13";
      scrollback.lines = 100000;
    };
  };

  home.packages = with pkgs; [
    libsixel # image support in foot
  ];
}
