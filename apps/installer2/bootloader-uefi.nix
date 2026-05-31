{ ... }: {
  boot.loader.systemd-boot = {
    enable = true;
    consoleMode = "0";
  };
  boot.loader.efi.canTouchEfiVariables = true;
}
