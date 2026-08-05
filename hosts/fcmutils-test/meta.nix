{
  disposable = true;
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
        router = "fcmutils-test";
        authKey = "tailscale_preauth_key";
      };
    }
    ../../modules/os/feat/linux/services/postfix.nix
    ../../modules/os/feat/linux/desktop/bspwm-minimal.nix
    ../../modules/os/feat/linux/services/xrdp.nix
  ];

  deployment = {
    vmid = "204";
    diskSize = "20";
    tailscaleNamespace = "fcm";
    proxmox = {
      provider = "pve1";
      bios = "ovmf";
      diskBus = "scsi";
      iso.customPath = "arthurz2-dir:iso/nixos-minimal-26.05-x86_64-linux-nxd-built.iso";
      cores = "4";
      memory = "4096";
    };
  };
}
