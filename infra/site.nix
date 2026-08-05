let
  mydefs = import ../defines.nix;
  inherit (mydefs) secretsSite;
  pveNodes = {
    pve1 = {
      cluster = "barcluster";
      address = "192.168.1.15";
      proxmoxNodeName = "pve-dl360p";
      defaultIsoStorage = "arthurz2-dir";
      defaultDiskStorage = "arthurz2-lvm";
      defaultGateway = "192.168.1.1";
      defaultNetwork = "virtio,bridge=vmbr1,tag=10";
      defaultDiscoverySubnets = [ "192.168.1.0/24" ];
    };
    pve2 = {
      cluster = "barcluster";
      address = "192.168.1.5";
      proxmoxNodeName = "pve2";
      defaultIsoStorage = "arthurz2-dir";
      defaultDiskStorage = "arthurz2-lvm";
      defaultGateway = "192.168.1.1";
      defaultNetwork = "virtio,bridge=vmbr1,tag=10";
      defaultDiscoverySubnets = [ "192.168.1.0/24" ];
    };
  };
in
{
  defaults = {
    tailscaleNamespace = "lamt";
    builderBySystem.x86_64-linux = "deploy@utils";
    sshIdentityPublicKey = mydefs.mySshAuthPublicKey;
  };

  providers.pve = {
    pve1 = {
      endpoint = "https://192.168.1.15:8006";
      credentialBinding = "secret/lamt-pve-api-token";
      rootCa = ../nxd/certs/pve-root-ca.pem;
      config = {
        expectedCluster = "barcluster";
        tokenId = "lamt-provision@pve!automation";
        tokenSecretBinding = "secret/lamt-pve-api-token";
        hostStateTransports.pve1 = {
          address = "192.168.1.15";
          user = "root";
          hostIdentity = "ssh-host-identity/pve1";
          identityAgentBinding = "env/SSH_AUTH_SOCK";
          identityPublicKey = mydefs.mySshAuthPublicKey;
        };
      };
    };
    pve2 = {
      endpoint = "https://192.168.1.5:8006";
      credentialBinding = "secret/lamt-pve-api-token";
      rootCa = ../nxd/certs/pve-root-ca.pem;
      config = {
        expectedCluster = "barcluster";
        tokenId = "lamt-provision@pve!automation";
        tokenSecretBinding = "secret/lamt-pve-api-token";
        hostStateTransports.pve2 = {
          address = "192.168.1.5";
          user = "root";
          hostIdentity = "ssh-host-identity/pve2";
          identityAgentBinding = "env/SSH_AUTH_SOCK";
          identityPublicKey = mydefs.mySshAuthPublicKey;
        };
      };
    };
  };
  providers.pbs.pbs = {
    credentialBindings = [
      "secret/pbs/pbs-r720/provision-token"
      "secret/pbs/pbs-r720-test/provision-token"
    ];
    config = {
      servers.pbs-r720 = {
        origin = "https://192.168.1.22:8007";
        caCertificatePem = builtins.readFile ../nxd/certs/pbs-root-ca.pem;
        tokenId = "lamt-provision@pbs!automation";
        tokenSecretBinding = "secret/pbs/pbs-r720/provision-token";
        trustMode = "exact-certificate";
      };
      servers.pbs-r720-test = {
        origin = "https://192.168.1.23:8007";
        caCertificatePem = builtins.readFile ../nxd/certs/pbs-r720-test.pem;
        tokenId = "lamt-provision@pbs!automation";
        tokenSecretBinding = "secret/pbs/pbs-r720-test/provision-token";
        trustMode = "exact-certificate";
      };
      hostStateTransports.pbs-r720 = {
        address = "192.168.1.22";
        user = "root";
        hostIdentity = "ssh-host-identity/pbs-r720";
        identityAgentBinding = "env/SSH_AUTH_SOCK";
        identityPublicKey = mydefs.mySshAuthPublicKey;
      };
      hostStateTransports.pbs-r720-test = {
        address = "192.168.1.23";
        user = "root";
        hostIdentity = "ssh-host-identity/pbs-r720-test";
        identityAgentBinding = "env/SSH_AUTH_SOCK";
        identityPublicKey = mydefs.mySshAuthPublicKey;
      };
      installTransports = {
        pve2 = {
          address = "192.168.1.5";
          user = "root";
          hostIdentity = "ssh-host-identity/pve2";
          identityAgentBinding = "env/SSH_AUTH_SOCK";
          identityPublicKey = mydefs.mySshAuthPublicKey;
        };
        pbs-r720-test = {
          address = "192.168.1.23";
          user = "root";
          hostIdentity = "ssh-host-identity/pbs-r720-test";
          identityAgentBinding = "env/SSH_AUTH_SOCK";
          identityPublicKey = mydefs.mySshAuthPublicKey;
        };
      };
    };
  };
  providers.vmware.vmware.arguments = [
    "--vmrun"
    "/Applications/VMware Fusion.app/Contents/Library/vmrun"
    "--vdiskmanager"
    "/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager"
  ];

  secrets.bindings = {
    lamt-pve-api-token = {
      resolver = "sops-age";
      document = "${secretsSite}/providers/pve.yaml";
      key = "token";
    };
    "pbs/pbs-r720/provision-token" = {
      resolver = "sops-age";
      document = "${secretsSite}/hosts/pbs-r720/pbs-r720.yaml";
      key = "provision-token";
    };
    "pbs/pbs-r720/pve-backup-token" = {
      resolver = "sops-age";
      document = "${secretsSite}/hosts/pbs-r720/pbs-r720.yaml";
      key = "pve-backup-token";
    };
    "pbs/pbs-r720/fingerprint" = {
      resolver = "sops-age";
      document = "${secretsSite}/hosts/pbs-r720/pbs-r720.yaml";
      key = "pbs-r720-fingerprint";
    };
    "pve/host-backup-age-recipients" = {
      resolver = "sops-age";
      document = "${secretsSite}/recovery/pve-host-backup.yaml";
      key = "age-recipients";
    };
    "pbs/pbs-r720-test/provision-token" = {
      resolver = "sops-age";
      document = "${secretsSite}/hosts/pbs-r720-test/pbs-r720-test.yaml";
      key = "provision-token";
    };
    "pbs/pbs-r720-test/pve-backup-token" = {
      resolver = "sops-age";
      document = "${secretsSite}/hosts/pbs-r720-test/pbs-r720-test.yaml";
      key = "pve-backup-token";
    };
    "pbs/pbs-r720-test/fingerprint" = {
      resolver = "sops-age";
      document = "${secretsSite}/hosts/pbs-r720-test/pbs-r720-test.yaml";
      key = "pbs-r720-test-fingerprint";
    };
  };

  vmware = {
    isoDirectory = "/Users/lamt/Virtual Machines.localized/VMWIsoImages";
    vmrun = "/Applications/VMware Fusion.app/Contents/Library/vmrun";
    vdiskmanager = "/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager";
    installer = "/Users/lamt/Virtual Machines.localized/VMWIsoImages/nixos-minimal-25.11.20260522.b77b3de-aarch64-linux.iso";
    installerSha256 = "6ca9735acc69ef42d0a6ffcd4fa45f8bf75da160136c868c8153063c726f584d";
  };

  clusters = {
    barcluster = {
      apiPreference = [
        "pve1"
        "pve2"
      ];
      qdeviceState = "present";
      qdeviceNodeId = "pve1";
      qnetEndpoint = "medo-qnet.lamhub.com";
      qnetHostIdentity = "ssh-host-identity/medo";
      nodes = [
        "pve1"
        "pve2"
      ];
    };
  };

  nodes = pveNodes;

  hosts = {
    avon.targetIp = "192.168.1.18";
    fcmbuilder.targetIp = "192.168.7.10";
    fcmutils.targetIp = "192.168.7.9";
    # Inventory-only guests (backup job membership); names match live PVE guest names.
    # Their endpoints are provider-observed and are not authored deployment targets.
    pbs-r720.targetIp = "192.168.1.22";
    pbs-r720-test.targetIp = "192.168.1.23";
    pve1.targetIp = pveNodes.pve1.address;
    pve2.targetIp = pveNodes.pve2.address;
    pve-test.targetIp = "192.168.250.10";
    router-backup.targetIp = "192.168.1.3";
    router-main.targetIp = "192.168.1.2";
    router-recovery.targetIp = "192.168.1.20";
    utils.targetIp = "192.168.1.19";
  };

  pveAccess = {
    provider = "pve1";
    roles = {
      NXDOperator.privileges = [
        "Datastore.Allocate"
        "Datastore.AllocateSpace"
        "Datastore.AllocateTemplate"
        "Datastore.Audit"
        "Mapping.Audit"
        "Mapping.Modify"
        "Permissions.Modify"
        "Sys.Audit"
        "Sys.Modify"
        "VM.Audit"
        "VM.Backup"
        "VM.Config.CDROM"
        "VM.Config.CPU"
        "VM.Config.Cloudinit"
        "VM.Config.Disk"
        "VM.Config.HWType"
        "VM.Config.Memory"
        "VM.Config.Network"
        "VM.Config.Options"
        "VM.Console"
        "VM.GuestAgent.Audit"
        "VM.Migrate"
        "VM.PowerMgmt"
        "VM.Snapshot"
        "VM.Snapshot.Rollback"
      ];
      NXDProvisioner.privileges = [
        "VM.Allocate"
        "VM.Clone"
      ];
      NXDInstallerHostKeyReader.privileges = [ "VM.GuestAgent.FileRead" ];
      NXDNetworkUser.privileges = [ "SDN.Use" ];
      NXDStorageOperator.privileges = [
        "Datastore.Audit"
        "Datastore.Allocate"
        "Datastore.AllocateSpace"
        "Datastore.AllocateTemplate"
      ];
      NXDBackupJob.privileges = [
        "Datastore.Audit"
        "Datastore.AllocateSpace"
      ];
    };
    acls =
      let
        principals = [
          "lamt-provision@pve"
          "lamt-provision@pve!automation"
        ];
        matrix = [
          {
            combo = "operator";
            path = "/";
            role = "NXDOperator";
          }
          {
            combo = "operator-vms";
            path = "/vms";
            role = "NXDOperator";
          }
          {
            combo = "provisioner";
            path = "/vms";
            role = "NXDProvisioner";
          }
          {
            combo = "installer-host-key-reader";
            path = "/vms";
            role = "NXDInstallerHostKeyReader";
          }
          {
            combo = "network-localnetwork";
            path = "/sdn/zones/localnetwork";
            role = "NXDNetworkUser";
          }
          {
            combo = "storage-arthurz2-dir";
            path = "/storage/arthurz2-dir";
            role = "NXDStorageOperator";
          }
          {
            combo = "storage-arthurz2-lvm";
            path = "/storage/arthurz2-lvm";
            role = "NXDStorageOperator";
          }
          {
            combo = "storage-pbs-r720-backup";
            path = "/storage/pbs-r720-backup";
            role = "NXDStorageOperator";
          }
          {
            combo = "storage-pbs-r720-backup-job";
            path = "/storage/pbs-r720-backup";
            role = "NXDBackupJob";
          }
          {
            combo = "storage-pbs-r720-test-backup";
            path = "/storage/pbs-r720-test-backup";
            role = "NXDStorageOperator";
          }
          {
            combo = "storage-pbs-r720-test-backup-job";
            path = "/storage/pbs-r720-test-backup";
            role = "NXDBackupJob";
          }
        ];
      in
      builtins.concatMap (
        item:
        map (principal: {
          id = "${item.combo}-${builtins.replaceStrings [ "@" "!" ] [ "-" "-" ] principal}";
          path = item.path;
          role = item.role;
          inherit principal;
        }) principals
      ) matrix;
  };

  backupServers.pbs-r720 = {
    provider = "provider/pbs";
    address = "192.168.1.22";
    guest = "guest/pbs-r720";
    pveNode = "pve2";
    state = "present";
  };
  backupServers.pbs-r720-test = {
    disposable = true;
    provider = "provider/pbs";
    address = "192.168.1.23";
    pveNode = "pve2";
    state = "present";
    installAppliance = {
      pveTransport = "pve2";
      guestTransport = "pbs-r720-test";
      hostIdentity = "ssh-host-identity/pbs-r720-test";
      hostIdentitySecretBinding = "secret/bar/hosts/pbs-r720-test/ssh-host-ed25519";
      isoCompose = {
        sourceIsoPath = "/var/lib/vz/template/iso/proxmox-backup-server_4.2-1.iso";
        sourceIsoUrl = "https://download.proxmox.com/iso/proxmox-backup-server_4.2-1.iso";
        sourceIsoSha256 = "2fb299deac3929253712c9c3dfc9237edbe70af83c8848467616b771a1d5453e";
        answerTomlPath = "/var/lib/nxd/pbs-install/pbs-r720-test/answer.toml";
        firstBootScriptPath = "/var/lib/nxd/pbs-install/pbs-r720-test/first-boot.sh";
        outputIsoPath = "/var/lib/vz/template/iso/pbs-r720-test-auto.iso";
        answer = {
          fqdn = "pbs-r720-test.lamhub.com";
          mailto = mydefs.gitUserEmail;
          timezone = mydefs.timeZone;
          country = "au";
          keyboard = "en-us";
          cidr = "192.168.1.23/24";
          gateway = "192.168.1.1";
          dns = "192.168.1.1";
          disk = "sda";
          rootSshPublicKey = mydefs.mySshAuthPublicKey;
        };
      };
      guestCreate = {
        targetId = "guest/pbs-r720-test";
        providerInstance = "provider/pve2";
        vmid = 923;
        name = "pbs-r720-test";
        diskStorage = "local-zfs";
        efiStorage = "local-zfs";
        isoStorage = "local";
        isoVolumeName = "pbs-r720-test-auto.iso";
        net0 = "virtio,bridge=vmbr1,tag=10";
        onBoot = false;
        bios = "ovmf";
        startAfterCreate = true;
      };
      waitInstall = {
        markerPath = "/root/.nxd-pbs-installed";
        expectedMarkerContent = "nxd-pbs-installed";
      };
      finalizeMedia = {
        outputIsoPath = "/var/lib/vz/template/iso/pbs-r720-test-auto.iso";
        vmid = 923;
        expectedName = "pbs-r720-test";
        targetId = "guest/pbs-r720-test";
        providerInstance = "provider/pve2";
        diskStorage = "local-zfs";
        efiStorage = "local-zfs";
        isoStorage = "local";
        isoVolumeName = "pbs-r720-test-auto.iso";
        net0 = "virtio,bridge=vmbr1,tag=10";
        onBoot = false;
        bios = "ovmf";
      };
    };
  };
  guests.pbs-r720-test = {
    disposable = true;
    id = "pbs-r720-test";
    provider = "provider/pve2";
    guestType = "qemu";
    vmid = 923;
    name = "pbs-r720-test";
    node = "pve2";
    onBoot = false;
    startupOrder = 999;
    startupUp = 0;
    startupDown = 0;
  };
  datastores."pbs-r720/arthurz2-pbs" = {
    provider = "provider/pbs";
    backupServer = "backup-server/pbs-r720";
    datastoreId = "arthurz2-pbs";
    path = "/mnt/arthur_z2/PBS/pbs-r720";
    backingMount = {
      source = "192.168.1.6:/mnt/arthur_z2/PBS";
      mountPoint = "/mnt/arthur_z2/PBS";
      fileSystem = "nfs";
      options = [
        "defaults"
        "_netdev"
        "nofail"
        "x-systemd.automount"
        "vers=3"
      ];
    };
    garbageCollectionSchedule = "Sun 02:00";
    state = "present";
  };
  datastores."pbs-r720-test/arthurz2-pbs-test" = {
    provider = "provider/pbs";
    backupServer = "backup-server/pbs-r720-test";
    datastoreId = "arthurz2-pbs-test";
    path = "/mnt/datastore/arthurz2-pbs-test";
    garbageCollectionSchedule = "Sun 02:00";
    state = "present";
  };
  backupNamespaces."pbs-r720/arthurz2-pbs/lamt" = {
    provider = "provider/pbs";
    datastore = "datastore/pbs-r720/arthurz2-pbs";
    namespace = "lamt";
    default = true;
    operatorAccess = true;
    state = "present";
  };
  backupNamespaces."pbs-r720-test/arthurz2-pbs-test/lamt-test" = {
    provider = "provider/pbs";
    datastore = "datastore/pbs-r720-test/arthurz2-pbs-test";
    namespace = "lamt-test";
    default = true;
    operatorAccess = true;
    state = "present";
  };
  accessPrincipals = {
    "pbs-r720-test/provision" = {
      provider = "provider/pbs";
      backupServer = "backup-server/pbs-r720-test";
      principalId = "lamt-provision@pbs!automation";
      principalType = "token";
      tokenSecretBinding = "secret/pbs/pbs-r720-test/provision-token";
      installBootstrap.transport = "pbs-r720-test";
      state = "present";
    };
    "pbs-r720/pve-backup" = {
      provider = "provider/pbs";
      backupServer = "backup-server/pbs-r720";
      principalId = "pve-backup@pbs!lamt";
      principalType = "token";
      tokenSecretBinding = "secret/pbs/pbs-r720/pve-backup-token";
      state = "present";
    };
    "pbs-r720/pve-backup-user" = {
      provider = "provider/pbs";
      backupServer = "backup-server/pbs-r720";
      principalId = "pve-backup@pbs";
      principalType = "user";
      state = "present";
    };
    "pbs-r720-test/pve-backup" = {
      provider = "provider/pbs";
      backupServer = "backup-server/pbs-r720-test";
      principalId = "pve-backup@pbs!lamt";
      principalType = "token";
      tokenSecretBinding = "secret/pbs/pbs-r720-test/pve-backup-token";
      state = "present";
    };
    "pbs-r720-test/pve-backup-user" = {
      provider = "provider/pbs";
      backupServer = "backup-server/pbs-r720-test";
      principalId = "pve-backup@pbs";
      principalType = "user";
      state = "present";
    };
  };
  accessGrants = {
    "pbs-r720/pve-backup" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720/pve-backup";
      path = "/datastore/arthurz2-pbs/lamt";
      role = "DatastoreBackup";
      state = "present";
    };
    "pbs-r720/pve-backup-DatastoreReader" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720/pve-backup";
      path = "/datastore/arthurz2-pbs/lamt";
      role = "DatastoreReader";
      state = "present";
    };
    "pbs-r720/pve-backup-user" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720/pve-backup-user";
      path = "/datastore/arthurz2-pbs/lamt";
      role = "DatastoreBackup";
      state = "present";
    };
    "pbs-r720/pve-backup-user-DatastoreReader" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720/pve-backup-user";
      path = "/datastore/arthurz2-pbs/lamt";
      role = "DatastoreReader";
      state = "present";
    };
    "pbs-r720-test/pve-backup" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720-test/pve-backup";
      path = "/datastore/arthurz2-pbs-test/lamt-test";
      role = "DatastoreBackup";
      state = "present";
    };
    "pbs-r720-test/pve-backup-DatastoreReader" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720-test/pve-backup";
      path = "/datastore/arthurz2-pbs-test/lamt-test";
      role = "DatastoreReader";
      state = "present";
    };
    "pbs-r720-test/pve-backup-user" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720-test/pve-backup-user";
      path = "/datastore/arthurz2-pbs-test/lamt-test";
      role = "DatastoreBackup";
      state = "present";
    };
    "pbs-r720-test/pve-backup-user-DatastoreReader" = {
      provider = "provider/pbs";
      principal = "access-principal/pbs-r720-test/pve-backup-user";
      path = "/datastore/arthurz2-pbs-test/lamt-test";
      role = "DatastoreReader";
      state = "present";
    };
  };
  storage.pbs-r720-backup = {
    provider = "provider/pve2";
    storageType = "pbs";
    content = [ "backup" ];
    pbsServer = "192.168.1.22";
    pbsDatastore = "arthurz2-pbs";
    pbsUsername = "pve-backup@pbs!lamt";
    pbsNamespace = "lamt";
    pbsPasswordBinding = "secret/pbs/pbs-r720/pve-backup-token";
    pbsFingerprintBinding = "secret/pbs/pbs-r720/fingerprint";
    tags = [ "operation:pve" ];
  };
  storage.pbs-r720-test-backup = {
    provider = "provider/pve2";
    storageType = "pbs";
    content = [ "backup" ];
    pbsServer = "192.168.1.23";
    pbsDatastore = "arthurz2-pbs-test";
    pbsUsername = "pve-backup@pbs!lamt";
    pbsNamespace = "lamt-test";
    pbsPasswordBinding = "secret/pbs/pbs-r720-test/pve-backup-token";
    pbsFingerprintBinding = "secret/pbs/pbs-r720-test/fingerprint";
  };

  # One cluster-wide PVE backup job (excludes PBS appliance VMID 122).
  backupJobs = {
    lamt-workloads-to-pbs-r720 = {
      # Plan/apply via either PVE API; guests span pve1 and pve2.
      provider = "provider/pve1";
      targetStorage = "pbs-r720-backup";
      schedule = "02:30";
      mode = "snapshot";
      compression = "zstd";
      enabled = true;
      tags = [ "operation:pve" ];
      guests = [
        "vyos-1.3-rolling"
        "avon"
        "router-main"
        "utils"
        "router-backup"
        "vyos-124-lambuilt28Mar2020"
        "freenas112R720"
      ];
    };
    lamt-workloads-to-pbs-r720-test = {
      provider = "provider/pve1";
      targetStorage = "pbs-r720-test-backup";
      schedule = "02:30";
      mode = "snapshot";
      compression = "zstd";
      enabled = false;
      guests = [
        "vyos-1.3-rolling"
        "avon"
        "router-main"
        "utils"
        "router-backup"
        "vyos-124-lambuilt28Mar2020"
        "freenas112R720"
      ];
    };
  };

  pveStorage = {
    local = {
      storageType = "dir";
      path = "/var/lib/vz";
      content = [
        "iso"
        "vztmpl"
        "backup"
        "snippets"
      ];
    };
  };

  pveHostBackups.pve1 = {
    provider = "provider/pve1";
    nodeId = "pve1";
    backupServer = "backup-server/pbs-r720";
    accessPrincipal = "access-principal/pbs-r720/pve-backup";
    pbsDatastore = "arthurz2-pbs";
    pbsNamespace = "lamt";
    ageRecipientsBinding = "secret/pve/host-backup-age-recipients";
    schedule = "23:15";
    maximumAge = 86400;
  };
}
