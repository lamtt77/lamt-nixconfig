args@{ ... }:
{ lib, ... }:

let
  targetInventory = args.infra.targetInventory or false;
  headscaleEnabled = !targetInventory || args.infra.hostMeta ? medo-test;
  hostNames = import ./host-identities.nix;
  inherit (import ../defines.nix) secretsSite;
  siteOf = name: args.infra.hostMeta.${name}.nxd.secretsSite or secretsSite;
in
{
  nxd.secrets = args.infra.site.secrets // {
    bindings =
      args.infra.site.secrets.bindings
      // lib.listToAttrs (
        map (name: {
          name = "${siteOf name}/hosts/${name}/ssh-host-ed25519";
          value = {
            resolver = "sops-age";
            document = "${siteOf name}/hosts/${name}/${name}.yaml";
            key = "ssh-host-ed25519";
          };
        }) hostNames
      )
      // lib.optionalAttrs headscaleEnabled (
        {
          "headscale/api-token" = {
            resolver = "sops-age";
            document = "${secretsSite}/hosts/avon/avon.yaml";
            key = "headscale-api-token";
          };
        }
        // lib.listToAttrs (
          map (name: {
            name = "hosts/${name}/tailscale-preauth-key";
            value = {
              resolver = "sops-age";
              document = "${siteOf name}/hosts/${name}/${name}.yaml";
              key = "tailscale_preauth_key";
            };
          }) hostNames
        )
      );
    publicBindings =
      (args.infra.site.secrets.publicBindings or { })
      // lib.listToAttrs (
        map (name: {
          name = "${siteOf name}/hosts/${name}/identity";
          value = {
            resolver = "sops-age";
            document = "${siteOf name}/hosts/${name}/identity.json";
          };
        }) hostNames
      );
  };
}
