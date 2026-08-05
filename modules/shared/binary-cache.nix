# Single definition of the `nxd.binaryCache` option and its default.
#
# Two consumers need the same option and must not drift apart:
#   - hosts/meta-options.nix   validates host metadata in infra/default.nix
#   - modules/shared/options.nix  exposes it to NixOS/HM via lib/systems.nix
#
# The namespace is `nxd` rather than a site name: infra/default.nix projects
# this value into `deployment.binaryCache`, which NXD reads to configure the
# installer before any NixOS configuration exists on the target. A site's cache
# is chosen by the *value* (e.g. defs.fcmBinaryCache), never by the namespace.
{ lib }:
{
  binaryCacheType = lib.types.submodule {
    options = {
      url = lib.mkOption { type = lib.types.str; };
      publicKey = lib.mkOption { type = lib.types.str; };
      caCertificate = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          PEM of the CA that signed the cache's TLS certificate. Required only
          for caches using a private CA (FCM's Caddy `tls internal`); leave
          empty for publicly trusted certificates such as ACME.
        '';
      };
    };
  };

  defaultBinaryCache = {
    url = "https://cache.lamhub.com?priority=10";
    publicKey = "cache.lamhub.com-1:D/ywCfChYM7EGJ3UbQsH2YX8Svq2okabE+qdalC4fdw=";
  };
}
