{ lib, hostname, ... }:

{
  networking = {
    firewall.enable = lib.mkDefault false;
    hostName = lib.mkDefault hostname;
    useDHCP = lib.mkDefault true;
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # Enable tailscale. We manually authenticate when we want with
  # "sudo tailscale up". If you don't use tailscale, you should comment
  # out or delete all of this.
  services.tailscale.enable = false;
}
