args@{ ... }:
{ lib, ... }:

let
  targetInventory = args.infra.targetInventory or false;
  headscaleEnabled = !targetInventory || args.infra.hostMeta ? medo-test;
in
{
  nxd.providers =
    args.infra.site.providers
    // lib.optionalAttrs headscaleEnabled {
      headscale.headscale = {
        credentialBinding = "secret/headscale/api-token";
        endpoint = "https://ts.lamhub.com";
        rootCa = ./certs/headscale-root-ca.pem;
        config = {
          apiTokenBinding = "secret/headscale/api-token";
          connectTimeoutMs = 5000;
          requestTimeoutMs = 15000;
        };
      };
    };
}
