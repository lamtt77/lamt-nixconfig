{
  ...
}:

{
  config = {
    # LamT: TODO may not need if using bin/nixos-wsl-prep.ps1
    # Prevent systemd from suspending, sleeping, or hibernating the instance
    systemd.targets.sleep.enable = false;
    systemd.targets.suspend.enable = false;
    systemd.targets.hibernate.enable = false;
    systemd.targets.hybrid-sleep.enable = false;

    # Systemd-logind overrides
    services.logind.settings = {
      Login = {
        IdleAction = "ignore";
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
      };
    };
  };
}
