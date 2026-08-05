let
  defs = import ../../defines.nix;
in
{
  class = "nixos";
  system = "x86_64-linux";
  username = "deploy";
  server = true;
  hasDisko = true;

  role = "builder";
  osFeatures = [
    ../../modules/os/feat/linux/services/openssh.nix
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        router = "fcmbuilder";
        authKey = "tailscale_preauth_key";
      };
    }
    {
      module = ../../modules/os/feat/linux/services/nix-cache-server.nix;
      args = {
        bindAddress = "127.0.0.1";
        caddyProxy = true;
        caddyInternalTls = true;
        domain = "192.168.7.10";
        signKeySecretName = "fcmbuilder_nix_cache_signing_key";
      };
    }
  ];

  nxd.binaryCache = defs.fcmBinaryCache;
  nxd.secretsSite = "fcm";

  deployment = {
    diskSize = "100";
    tailscaleNamespace = "fcm";
  };
}
