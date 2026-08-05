# VirtIO driver setup for Proxmox / ESXi virtualization guest
{
  lib,
  ...
}:
{
  boot.initrd.availableKernelModules = [
    "ahci"
    "ata_piix"
    "sd_mod"
    "virtio_blk"
    "virtio_pci"
    "virtio_scsi"
    "vmw_pvscsi"
    "xhci_pci"
  ];

  boot.kernelModules = [ "vmxnet3" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
