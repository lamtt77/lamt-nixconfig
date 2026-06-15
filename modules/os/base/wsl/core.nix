{
  mydefs,
  myargs,
  pkgs,
  ...
}:
{
  wsl = {
    enable = true;
    defaultUser = myargs.username;
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt"; # this is the default behavior
    wslConf.network.hostname = myargs.hostname;

    # Enable native Docker support
    # docker-native.enable = true;

    # Enable integration with Docker Desktop (needs to be installed)
    # docker-desktop.enable = true;
  };

  # Keep WSL 2 VM alive in the background so services (e.g. Tailscale/sshd) stay reachable.
  systemd.services.wsl-keepalive = {
    description = "Keep WSL 2 VM alive";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      Restart = "always";
    };
  };

  # virtualisation.docker = {
  #   enable = true;
  #   enableOnBoot = true;
  #   autoPrune.enable = true;
  # };

  system.stateVersion = mydefs.stateVersion;
}
