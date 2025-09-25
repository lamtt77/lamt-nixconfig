{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.hm.base.polkit;
in {
  options.modules.hm.base.polkit = with types; {
    enable = mkEnableOption "Polkit Gnome";
  };

  config = mkIf cfg.enable {
    systemd.user.services.polkit-gnome-authentication-agent-1 = {
      Unit = {
        Description = "polkit-gnome-authentication-agent-1";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        Environment = "";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    home.packages = [pkgs.polkit_gnome];
  };
}
