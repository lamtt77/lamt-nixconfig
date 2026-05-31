{ mydefs, ... }: {
  # This is a non-NixOS VM definition used purely for Proxmox cloud-init template provisioning tests.
  # We do not build NixOS system closure for it, but installer-rs queries its deployment metadata.
  deployment = {
    vmid = "201";
    proxmox = {
      host = mydefs.hosts.pve1.ip;
      bios = "seabios";
      diskBus = "scsi";
      scsiHw = "virtio-scsi-pci"; # VirtIO SCSI controller (resolves "crng init done" hang on boot)
      cloudInit = {
        image = "/mnt/pve/arthurz2-dir/images/ubuntu-22.04-server-cloudimg-amd64.img";
        user = "ubuntu";
        ipconfig0 = "ip=dhcp";
      };
    };
  };
}

