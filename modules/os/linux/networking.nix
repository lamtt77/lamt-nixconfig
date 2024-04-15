{ lib, hostname, ... }:

{
  networking = {
    firewall.enable = lib.mkDefault true;
    hostName = lib.mkDefault hostname;
    useDHCP = lib.mkDefault true;
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # Enable tailscale. We manually authenticate when we want with "sudo tailscale up"
  services.tailscale.enable = false;
}
