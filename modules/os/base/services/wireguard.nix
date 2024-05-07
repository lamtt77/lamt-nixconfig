{ config, lib, pkgs, hostname, ... }:

with lib;
let
  cfg = config.modules.os.base.services.wireguard;
in {
  options = with types; {
    modules.os.base.services.wireguard = {
      enable = mkEnableOption "Wireguard module";
    };
  };
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wireguard-go
      wireguard-tools
    ];

    environment.etc = {
      "wireguard/wg0do.conf" = {
        source = config.age.secrets."${hostname}/wireguard-wg0do.conf".path;
      };

      "wireguard/wg1fcm.conf" = {
        source = config.age.secrets."${hostname}/wireguard-wg1fcm.conf".path;
      };

      "wireguard/wg2fcmLAN.conf" = {
        source = config.age.secrets."${hostname}/wireguard-wg2fcmLAN.conf".path;
      };

      "wireguard/wg3arthurVyosLambuilt.conf" = {
        source = config.age.secrets."${hostname}/wireguard-wg3arthurVyosLambuilt.conf".path;
      };

      "wireguard/wg4arthurVyos.conf" = {
        source = config.age.secrets."${hostname}/wireguard-wg4arthurVyos.conf".path;
      };
    };
  };
}
