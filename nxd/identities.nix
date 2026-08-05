args@{ ... }:
{ lib, ... }:

let
  hostNames = import ./host-identities.nix;
  inherit (import ../defines.nix) secretsSite;
  # Hosts absent from hostMeta (inventory-only entries) keep the repository site.
  siteOf = name: args.infra.hostMeta.${name}.nxd.secretsSite or secretsSite;
in

{
  nxd.site.identities =
    lib.mapAttrs
      (
        _name: identity:
        identity
        // {
          tags = lib.unique ((identity.tags or [ ]) ++ [ "operation:identity" ]);
        }
      )
      (
        lib.genAttrs hostNames (name: {
          provider = "provider/identity";
          deploymentTarget = name;
          secretBinding = "secret/${siteOf name}/hosts/${name}/ssh-host-ed25519";
          publicBinding = "public/${siteOf name}/hosts/${name}/identity";
        })
      );
}
