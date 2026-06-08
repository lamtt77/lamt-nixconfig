{ myargs, ... }:
{
  programs.dconf.enable = true;

  home-manager.users.${myargs.username} =
    { config, ... }:
    {
      gtk = {
        enable = true;
        gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
        # gtk3.extraConfig = { gtk-application-prefer-dark-theme = true; };
        # gtk4.extraConfig = { gtk-application-prefer-dark-theme = true; };
      };

      # dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
    };
}
