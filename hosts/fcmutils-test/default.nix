{
  lib,
  ...
}:
{
  imports = [
    ../fcmutils
  ];

  networking.hostName = lib.mkForce "fcmutils-test";
}
