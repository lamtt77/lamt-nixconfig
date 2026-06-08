{
  lib,
  myargs,
  ...
}:
{
  networking = {
    firewall.enable = lib.mkDefault true;
    hostName = lib.mkDefault myargs.hostname;
    useDHCP = lib.mkDefault true;
  };
}
