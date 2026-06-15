{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    yt-dlp
  ];
}
