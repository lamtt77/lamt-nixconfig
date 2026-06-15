{ lib, ... }:
{
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

      sshProxyJump = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "SSH proxy jump host (e.g. user@host)";
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

      substituteOnDestination = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow target-side substitution during nix copy to the destination host";
      };

      enableLocalCache = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable cache.lamhub.com as a binary cache substituter on the host";
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

        diskStorage = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proxmox storage pool for VM disk provisioning. If empty, defaults to the installer's built-in default.";
        };

        network = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proxmox net0 bridge and configuration string. If empty, defaults to the installer's built-in default.";
        };

        extraNetworks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional Proxmox network configuration strings (net1, net2, etc.).";
        };

        net0 = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proxmox net0 bridge and configuration string. Overrides network when set.";
        };

        net1 = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proxmox net1 bridge and configuration string.";
        };

        bootstrap = {
          interface = lib.mkOption {
            type = lib.types.str;
            default = "net0";
            description = "VM interface name used for bootstrap (e.g. net0, net1).";
          };

          staticIp = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Temporary static IP assigned to the live installer environment.";
          };

          subnet = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Target subnet CIDR range or format (e.g. 192.168.1.0/24).";
          };

          gateway = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Default route gateway for installer bootstrap networking.";
          };

          vlan = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.unsigned;
            default = null;
            description = "Optional VLAN tag for guest interface tagging during bootstrap.";
          };
        };

        pxe = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to provision the VM for PXE booting (omitting CDROM attachment and boot order net0 first).";
        };

        iso = {
          type = lib.mkOption {
            type = lib.types.str;
            default = "std";
            description = "ISO flavor to use for NixOS installation. 'std' (default) uses the standard qemu ISO; 'vlan' uses the VLAN-capable ISO.";
          };

          storage = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "The Proxmox storage pool where the ISO is located. If empty, defaults to the installer's built-in default.";
          };

          customPath = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Full Proxmox storage path to a custom ISO (e.g., arthurz2-dir:iso/my-custom.iso). When set, overrides the type-based ISO selection entirely.";
          };
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

      wsl = {
        enable = lib.mkEnableOption "WSL provider deployment";

        windowsHost = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Windows OpenSSH host that owns the WSL distribution";
        };

        windowsUser = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Windows account used for OpenSSH and WSL lifecycle commands";
        };

        distribution = lib.mkOption {
          type = lib.types.str;
          default = "NixOS";
          description = "Managed WSL distribution name";
        };

        installRoot = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Absolute Windows path used by wsl.exe --import";
        };

        bootstrapUser = lib.mkOption {
          type = lib.types.str;
          default = "nixos";
          description = "Bootstrap Linux account configured in the minimal WSL image";
        };

        guestHost = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Optional stable SSH hostname or address for the WSL guest";
        };

        transport = lib.mkOption {
          type = lib.types.enum [
            "auto"
            "direct"
            "windows"
          ];
          default = "auto";
          description = "WSL guest management transport selection";
        };

      };
    };
  };
}
