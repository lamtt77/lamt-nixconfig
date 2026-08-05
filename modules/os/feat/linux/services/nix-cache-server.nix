# Reusable Nix binary cache *server* feature powered by Harmonia.
# Exposes the local /nix/store directly over HTTP/HTTPS.
#
# The client side is deliberately not here: a host consumes a cache by
# declaring `nxd.binaryCache`, which modules/os/base/core.nix turns into
# substituters, trusted public keys, and CA trust. Keep the two separate —
# serving a cache and consuming one are independent concerns.
{
  domain ? null,
  port ? 5000,
  bindAddress ? "127.0.0.1",
  acmeDomain ? null,
  nginxProxy ? false,
  caddyProxy ? false,
  caddyInternalTls ? false,
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

  # Open the port if binding directly to a public interface (not proxied via localhost).
  # Reverse proxies own their own firewall rules below.
  networking.firewall.allowedTCPPorts = lib.mkMerge [
    (lib.mkIf (bindAddress == "0.0.0.0" || bindAddress == "[::]") [ port ])
    (lib.mkIf (caddyProxy && domain != null) [ 443 ])
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
        ${lib.optionalString caddyInternalTls "tls internal"}
        reverse_proxy 127.0.0.1:${toString port}
      '';
    };
  };

  # Caddy creates its local CA below this directory when `tls internal` is
  # enabled. It must be retained so clients continue to trust the same CA.
  persist.state.directories = lib.mkIf (caddyProxy && caddyInternalTls) [
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0750";
    }
  ];
}
