{
  disposable = true;
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;
  role = "server";

  deployment = {
    vmid = "923";
    requireSecrets = false;
    diskSize = "20";
    proxmox = {
      diskStorage = "local-zfs";
      bios = "ovmf";
      diskBus = "scsi";
      scsiHw = "virtio-scsi-single";
      cores = "2";
      memory = "4096";
      net0 = "virtio,bridge=vmbr1,tag=10";
      iso = {
        storage = "local";
        customPath = "local:iso/pbs-r720-test-auto.iso";
      };
    };
  };
}
