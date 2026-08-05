{ lib, ... }:
let
  binaryCache = import ../modules/shared/binary-cache.nix { inherit lib; };
in
{
  options = {
    disposable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host is restricted to an explicit disposable test lane.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "Primary user of the system";
    };

    nxd.binaryCache = lib.mkOption {
      type = lib.types.nullOr binaryCache.binaryCacheType;
      default = binaryCache.defaultBinaryCache;
      description = "Optional signed HTTPS binary cache for the host and installer.";
    };

    nxd.secretsSite = lib.mkOption {
      type = lib.types.str;
      default = (import ../defines.nix).secretsSite;
      description = ''
        Directory under the secrets repository holding this host's material.
        Identity bindings are authored at evaluation time, so a host whose
        secrets live outside the repository's own site must say so here.
      '';
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

      sshIdentityPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Reviewed public key used to select the matching identity from the SSH agent";
      };

      builder = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Explicit remote builder target (e.g., user@host)";
      };

      buildOn = lib.mkOption {
        type = lib.types.enum [
          "auto"
          "local"
          "builder"
          "target"
          "instantiated"
          "native"
          "cross"
        ];
        default = "auto";
        description = "Nix realization placement; builder requires deployment.builder";
      };

      bootstrapUser = lib.mkOption {
		type = lib.types.str;
		default = "";
		description = "Explicit SSH user for an existing bootstrap or overwrite target";
      };

      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "DNS nameservers configured in the target environment during bootstrap.";
      };

      requireSecrets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Fail before deployment mutation unless the host installer SOPS input resolves";
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

      localEval = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Optional evaluation-placement override; null lets NXD resolve automatic builder-side evaluation";
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
        provider = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Stable logical ID of the Proxmox provider in consumer inventory";
        };

        node = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Stable logical ID of the Proxmox node that owns the VM";
        };

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

        discoverySubnets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Approved subnets used to discover this VM by MAC address";
        };

        extraNetworks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional Proxmox network configuration strings (net1, net2, etc.).";
        };

        net0 = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proxmox net0 bridge and configuration string. If empty, defaults to the provider default.";
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
          description = "Whether to provision the VM for PXE installation (omitting CDROM attachment and using disk-first with network fallback until installed-system readiness).";
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
            description = "PVE import volume ID for the cloud-init OS baseline image (e.g., arthurz2-dir:import/ubuntu.qcow2)";
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

        isoDirectory = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Directory containing or receiving VMware installer ISO images";
        };

        cores = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4;
        };

        memoryMiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4096;
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
