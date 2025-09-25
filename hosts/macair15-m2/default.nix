{pkgs, ...}: {
  modules.os.base.services.sops.enable = true;
  modules.os.base.services.wireguard.enable = true;

  modules.os.darwin.services.nfsd.enable = true;

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
