{
  config,
  lib,
  mydefs,
  ...
}:
with lib; let
  cfg = config.modules.os.linux.services.acme;
in {
  options.modules.os.linux.services.acme = {
    enable = mkEnableOption "ACME (Let's Encrypt) configuration";

    email = mkOption {
      type = types.str;
      default = "info@${mydefs.myDomain}";
      description = "Default email address for Let's Encrypt registration.";
    };

    domain = mkOption {
      type = types.str;
      default = mydefs.myDomain;
      description = "Primary domain for the wildcard certificate.";
    };

    extraDomainNames = mkOption {
      type = types.listOf types.str;
      default = [ "*.${mydefs.myDomain}" ];
      description = "Extra domain names (SANs) for the wildcard certificate.";
    };

    dnsProvider = mkOption {
      type = types.str;
      default = "cloudflare";
      description = "DNS provider for ACME DNS-01 challenge.";
    };

    dnsResolver = mkOption {
      type = types.str;
      default = "1.1.1.1:53";
      description = "DNS resolver address and port for ACME to use.";
    };

    secretName = mkOption {
      type = types.str;
      default = "cloudflare_dns_api_token";
      description = "The SOPS secret name for the DNS provider API token.";
    };

    staging = mkOption {
      type = types.bool;
      default = false;
      description = "Use Let's Encrypt staging environment.";
    };
  };

  config = mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults = {
        server = if cfg.staging
          then "https://acme-staging-v02.api.letsencrypt.org/directory"
          else "https://acme-v02.api.letsencrypt.org/directory";
        email = cfg.email;
        renewInterval = "weekly";
      };
      certs."${cfg.domain}" = {
        extraDomainNames = cfg.extraDomainNames;
        dnsResolver = cfg.dnsResolver;
        dnsProvider = cfg.dnsProvider;
        environmentFile = config.sops.secrets."${cfg.secretName}".path;
        extraLegoRenewFlags = [ "--ari-disable" ];
      };
    };

    sops.secrets."${cfg.secretName}" = {
      owner = "acme";
      group = "acme";
    };

    persist.state.directories = [
      {
        directory = "/var/lib/acme";
        user = "acme";
        group = "acme";
        mode = "0750";
      }
    ];
  };
}
