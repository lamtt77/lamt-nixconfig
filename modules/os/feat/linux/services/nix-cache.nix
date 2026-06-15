# Reusable Nix binary cache service feature powered by Harmonia.
# Exposes the local /nix/store directly over HTTP/HTTPS.
{
  domain ? null,
  port ? 5000,
  bindAddress ? "127.0.0.1",
  acmeDomain ? null,
  nginxProxy ? false,
  caddyProxy ? false,
  signKeySecretName ? null, # Set to e.g. "nix_cache_signing_key" to enable signing via SOPS
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hasSecret = signKeySecretName != null;
in
{
  services.harmonia = {
    cache = {
      enable = true;
      signKeyPaths = lib.mkIf hasSecret [ config.sops.secrets."${signKeySecretName}".path ];
      settings.bind = "${bindAddress}:${toString port}";
    };
  };

  # If a secret is defined, configure it in SOPS.
  sops.secrets = lib.mkIf hasSecret {
    "${signKeySecretName}" = {
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  # Open the port if binding directly to a public interface (not proxied via localhost)
  networking.firewall.allowedTCPPorts = lib.mkIf (bindAddress == "0.0.0.0" || bindAddress == "[::]") [
    port
  ];

  # Nginx reverse proxy configuration
  services.nginx = lib.mkIf (nginxProxy && domain != null) {
    enable = true;
    proxyCachePath."nix-cache" = {
      enable = true;
      keysZoneName = "nix-cache";
      keysZoneSize = "10m";
      maxSize = "50g";
      inactive = "60d";
    };
    virtualHosts."${domain}" = {
      forceSSL = acmeDomain != null;
      useACMEHost = acmeDomain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        extraConfig = ''
          proxy_cache nix-cache;
          proxy_cache_valid 200 302 60d;
          proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;

          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };

  # Caddy reverse proxy configuration
  services.caddy = lib.mkIf (caddyProxy && domain != null) {
    enable = true;
    virtualHosts."${domain}" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString port}
      '';
    };
  };
}
