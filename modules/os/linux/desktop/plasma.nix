# KDE Plasma (Wayland)
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.os.linux.desktop.plasma;
in {
  options.modules.os.linux.desktop.plasma = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.displayManager.sddm.wayland.enable = true;
    services.desktopManager.plasma6.enable = true;
  };
}
