{
  config,
  lib,
  mydefs,
  ...
}:
{
  imports = [
    ../medo
  ];

  networking.hostName = lib.mkForce "medo-test";
}
