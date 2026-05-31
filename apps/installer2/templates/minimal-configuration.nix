{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./extra-config.nix
    ./bootloader.nix
    {{NETWORK_IMPORT}}
  ];

  networking.hostName = "{{HOSTNAME}}";
}
