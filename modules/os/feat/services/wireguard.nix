{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    wireguard-go
    wireguard-tools
  ];

  # default at /run/secrets
  sops.secrets = {
    "wireguard-wg0do.conf" = { };
    "wireguard-wg1fcm.conf" = { };
    "wireguard-wg2fcmLAN.conf" = { };
    "wireguard-wg3arthurVyosLambuilt.conf" = { };
    "wireguard-wg4arthurVyos.conf" = { };
  };

  environment.etc = {
    "wireguard/wg0do.conf".source = config.sops.secrets."wireguard-wg0do.conf".path;
    "wireguard/wg1fcm.conf".source = config.sops.secrets."wireguard-wg1fcm.conf".path;
    "wireguard/wg2fcmLAN.conf".source = config.sops.secrets."wireguard-wg2fcmLAN.conf".path;
    "wireguard/wg3arthurVyosLambuilt.conf".source =
      config.sops.secrets."wireguard-wg3arthurVyosLambuilt.conf".path;
    "wireguard/wg4arthurVyos.conf".source = config.sops.secrets."wireguard-wg4arthurVyos.conf".path;
  };
}
