{lib, ...}: {
  options = {
    user = lib.mkOption {
      type = lib.types.str;
      description = "Primary user of the system";
    };

    deployment = {
      targetIp = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Target IP address, tailscale/magicDNS hostname, or FQDN of the node for remote deployment";
      };

      builder = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Explicit remote builder target (e.g., user@host)";
      };

      lowMem = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Apply RAM-constrained compilation limits ('yes' or 'no')";
      };

      vmid = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Target VM ID for Proxmox provisioning";
      };

      diskSize = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Target VM disk size in GB (e.g., '64')";
      };

      tailscaleNamespace = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Tailscale/Headscale namespace/user for the pre-auth key";
      };

      proxmox = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proxmox hypervisor host (IP or hostname) where the VM resides";
        };

        bios = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Firmware type for Proxmox VM ('ovmf' or 'seabios')";
        };

        diskBus = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Disk interface type for Proxmox VM ('scsi' or 'virtio')";
        };

        scsiHw = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "SCSI controller type for Proxmox VM (e.g. 'virtio-scsi-single', 'virtio-scsi-pci', 'lsi'). Only relevant when diskBus = 'scsi'. Defaults to 'virtio-scsi-single' for cloud-init VMs.";
        };

        cores = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Number of CPU cores for the VM (defaults to 4 if empty)";
        };

        memory = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "RAM size in MB for the VM (defaults to 4096 if empty)";
        };

        cloudInit = {
          image = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Path to the cloud-init OS baseline image on Proxmox";
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Default OS username for cloud-init";
          };

          ipconfig0 = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Networking configuration for primary interface (e.g., ip=dhcp)";
          };

          ipconfig1 = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Networking configuration for secondary interface";
          };
        };
      };

      digitalocean = {
        region = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "DigitalOcean droplet region (e.g., sgp1)";
        };

        size = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "DigitalOcean droplet instance size (e.g., s-1vcpu-1gb)";
        };

        image = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "DigitalOcean droplet source image (e.g., ubuntu-24-04-x64)";
        };
      };

      vmware = {
        vmxPath = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Absolute path to the VMware Fusion VM .vmx file";
        };
      };
    };
  };
}
