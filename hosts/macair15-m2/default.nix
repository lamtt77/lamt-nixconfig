{
  myargs,
  pkgs,
  ...
}:
{
  modules.os.base.services.sops.enable = true;
  modules.os.base.services.wireguard.enable = true;

  modules.os.base.services.tailscale.enable = false; # Use App Store client, do not run daemon
  environment.systemPackages = [ pkgs.tailscale ];
  modules.os.darwin.services.nfsd.enable = true;
  modules.os.base.services.builders.enable = true;

  networking.hostName = myargs.hostname;

  environment.etc."resolver/ts.lamhub.lan" = {
    text = "nameserver 100.100.100.100\n";
  };

  # # qemu builder
  # nix.linux-builder = {
  #   enable = true;
  #   ephemeral = true;
  #   # config = ({ ... }: {
  #   #   virtualisation.darwin-builder.diskSize = 30 * 1024;
  #   # });
  # };

  # # Disable auto-start, use 'sudo launchctl start org.nixos.linux-builder'
  # launchd.daemons.linux-builder.serviceConfig = {
  #   KeepAlive = lib.mkForce false;
  #   RunAtLoad = lib.mkForce false;
  # };
}
