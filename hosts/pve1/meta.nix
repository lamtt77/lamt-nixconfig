# Bare-metal PVE appliance, inventory-only and not a NixOS build target.
{
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;
  role = "server";

  deployment.requireSecrets = false;
}
