{ pkgs, ... }:
{
  services.dbus.implementation = "broker";
  services.dbus.packages = [ pkgs.gcr ];
}
