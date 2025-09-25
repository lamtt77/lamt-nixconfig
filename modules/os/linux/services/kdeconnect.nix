{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.os.linux.services.kdeconnect;
in {
  options = with types; {
    modules.os.linux.services.kdeconnect = {
      enable = mkEnableOption "kdeconnect service";
    };
  };

  config = mkIf cfg.enable {
    programs.kdeconnect = {
      enable = true;
      # GSConnect for gnome
      # package = pkgs.gnomeExtensions.gsconnect;
    };
  };
}
