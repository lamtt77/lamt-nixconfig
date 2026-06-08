{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.hm.base.yt-dlp;
in
{
  options.modules.hm.base.yt-dlp = with types; {
    enable = mkEnableOption "YouTube Downloader";
  };

  config = mkIf cfg.enable {
    programs.yt-dlp = {
      enable = true;
      settings = {
        embed-metadata = true;
        sponsorblock-mark = "all";
        downloader = lib.getExe pkgs.aria2;
      };
    };

    home.packages = [ pkgs.aria2 ];
  };
}
