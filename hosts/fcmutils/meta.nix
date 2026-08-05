let
  defs = import ../../defines.nix;
in
{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  role = "server";
  osFeatures = [
    ../../modules/os/feat/linux/services/openssh.nix
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        router = "fcmutils";
        authKey = "tailscale_preauth_key";
      };
    }
    ../../modules/os/feat/linux/services/postfix.nix
    ../../modules/os/feat/linux/desktop/bspwm-minimal.nix
    ../../modules/os/feat/linux/services/xrdp.nix
  ];

  hmFeatures = [
    ../../modules/hm/feat/term/kitty.nix
    ../../modules/hm/feat/term/tmux.nix
  ];

  nxd.binaryCache = defs.fcmBinaryCache;
  nxd.secretsSite = "fcm";

  deployment = {
    diskSize = "20";
    tailscaleNamespace = "fcm";
    # Build on the FCM-site builder. The site default (utils) sits on another
    # segment and can reach neither this host's network nor the cache it trusts.
    builder = "deploy@fcmbuilder";
  };
}
