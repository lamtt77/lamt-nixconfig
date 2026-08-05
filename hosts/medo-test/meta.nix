let
  headscaleAuthKey = "tailscale_preauth_key";
in
{
  disposable = true;
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  role = "server";
  osFeatures = [
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        router = "medo-test";
        authKey = headscaleAuthKey;
      };
    }
    ../../modules/os/feat/linux/services/openssh.nix
    ../../modules/os/feat/linux/services/fail2ban.nix
  ];

  deployment = {
    vmid = "203";
    lowMem = "yes";
    requireSecrets = true;
    diskSize = "20";
    proxmox = {
      provider = "pve1";
      bios = "seabios";
      diskBus = "virtio";
      iso.customPath = "arthurz2-dir:iso/nixos-minimal-26.05-x86_64-linux-nxd-built.iso";
      cores = "1";
      memory = "1024";
    };
  };
}
