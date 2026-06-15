{
  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "10s";
  };
  services.journald.extraConfig = "SystemMaxUse=300M";
}
