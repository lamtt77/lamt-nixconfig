{
  lib,
  ...
}:
{
  imports = [
    ../medo
  ];

  networking.hostName = lib.mkForce "medo-test";
  networking.nameservers = lib.mkForce [ ];

  services.qemuGuest.enable = true;

}
