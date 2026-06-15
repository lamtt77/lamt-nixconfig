{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  my,
  myargs,
  ...
}:
{
  imports = [
    ./hardware-avon.nix
    (import ../_disko/generic.nix {
      inherit inputs;
      disks = [ "/dev/sda" ];
      ephemeral = true;
    })
  ];

  # Note: If you ever need to resize the disk, you can grow the persistent partition manually by running:
  #   sudo growpart /dev/sda 2
  #   sudo resize2fs /dev/sda2

  networking =
    my.mkStaticNetworking (
      mydefs.networkingDefaults
      // {
        ip = config.deployment.targetIp;
        interface = "ens18";
      }
    )
    // {
      # iperf testing port
      firewall.allowedTCPPorts = [ 5201 ];
      firewall.allowedUDPPorts = [ 5201 ];
    };

  fileSystems."/mnt/VM" = {
    device = mydefs.hosts.avon.nas;
    fsType = "nfs";
  };

  persist.state.directories = [
    "/var/lib/nixos"
    "/var/lib/tailscale"
    "/var/lib/docker"
    "/var/log/journal"
    "/home/${myargs.username}"
  ];
  persist.state.files = [
    "/etc/machine-id"
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key.pub"
    "/etc/ssh/ssh_host_rsa_key"
    "/etc/ssh/ssh_host_rsa_key.pub"
  ];

  virtualisation.docker.enable = true;

  services.qemuGuest.enable = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=2G"
      "mode=755"
    ];
  };

  fileSystems."/persist".neededForBoot = true;

  fileSystems."/nix" = {
    device = "/persist/nix";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };

  # Decrypt Cloudflare Tunnel credentials
  # sops.secrets.cloudflared-tunnel-creds = {
  #   owner = "cloudflared";
  #   group = "cloudflared";
  # };

  # Configure Cloudflare Tunnel pointing directly to Headscale
  # services.cloudflared = {
  #   tunnels = {
  #     "696fcf40-1a29-4314-8268-2e60de74ef0f" = {
  #       credentialsFile = config.sops.secrets.cloudflared-tunnel-creds.path;
  #       default = "http_status:404";
  #       ingress = {
  #         "ts.lamhub.com" = {
  #           service = "https://localhost:443";
  #           originRequest = {
  #             noTLSVerify = true;
  #           };
  #         };
  #       };
  #     };
  #   };
  # };
}
