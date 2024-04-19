{ lib, hostname, ... }:

{
  networking = {
    firewall.enable = lib.mkDefault true;
    hostName = lib.mkDefault hostname;
    useDHCP = lib.mkDefault true;
  };
}
