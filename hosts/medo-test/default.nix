{ config, lib, mydefs, ... }: {
  imports = [
    ../medo
  ];

  networking.hostName = lib.mkForce "medo-test";

  # Override DigitalOcean deployment configurations with Proxmox settings for testing
  deployment = {
    vmid = "203";
    targetIp = "";
    lowMem = "yes";
    diskSize = "20";
    proxmox = {
      host = mydefs.hosts.pve1.ip;
      bios = "seabios";  # Matches DigitalOcean legacy GRUB boot
      diskBus = "virtio"; # Exposes disk as /dev/vda to match DigitalOcean virtual disk layout
      cores = "1";
      memory = "1024";
    };
    digitalocean = lib.mkForce {
      region = "";
      size = "";
      image = "";
    };
  };
}
