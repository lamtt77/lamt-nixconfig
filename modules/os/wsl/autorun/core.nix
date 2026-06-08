{
  mydefs,
  myargs,
  ...
}:
{
  wsl = {
    enable = true;
    defaultUser = myargs.username;
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt"; # this is the default behavior

    # Enable native Docker support
    # docker-native.enable = true;

    # Enable integration with Docker Desktop (needs to be installed)
    # docker-desktop.enable = true;
  };

  # virtualisation.docker = {
  #   enable = true;
  #   enableOnBoot = true;
  #   autoPrune.enable = true;
  # };

  system.stateVersion = mydefs.stateVersion;
}
