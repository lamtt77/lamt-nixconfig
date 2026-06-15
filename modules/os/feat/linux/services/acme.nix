{
  email ? null, # defaults to info@<domain> computed inside
  domain ? "lamhub.com",
  extraDomainNames ? [ "*.lamhub.com" ],
  dnsProvider ? "cloudflare",
  dnsResolver ? "1.1.1.1:53",
  secretName ? "cloudflare_dns_api_token",
  staging ? false,
}:
{
  config,
  lib,
  mydefs,
  ...
}:
let
  effectiveEmail = if email != null then email else "info@${domain}";
in
{
  security.acme = {
    acceptTerms = true;
    defaults = {
      server =
        if staging then
          "https://acme-staging-v02.api.letsencrypt.org/directory"
        else
          "https://acme-v02.api.letsencrypt.org/directory";
      email = effectiveEmail;
      renewInterval = "weekly";
    };
    certs."${domain}" = {
      inherit extraDomainNames dnsResolver dnsProvider;
      environmentFile = config.sops.secrets."${secretName}".path;
      extraLegoRenewFlags = [ "--ari-disable" ];
    };
  };

  sops.secrets."${secretName}" = {
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
}
