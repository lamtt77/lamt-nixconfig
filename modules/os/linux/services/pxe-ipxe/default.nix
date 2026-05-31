{ config,
  pkgs,
  lib,
  mydefs,
  ...}: with lib; let
  cfg = config.modules.os.linux.services.pxe-ipxe;

  # ============================================================================
  # Helpers
  # ============================================================================

  mkConfigTarball = name: src: excludeList:
    pkgs.runCommand "${name}.tar.gz" { nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ]; } ''
      tar --owner=0 --group=0 --numeric-owner --sort=name --mtime="@0" \
        ${concatMapStringsSep " " (p: "--exclude='${p}'") excludeList} \
        -czvf $out -C ${src} .
    '';

  mkAnswerNetworkConfig = ip: ''
    source = "from-answer"
    cidr = "${ip}/${mydefs.networkingDefaults.netmask}"
    dns = "${mydefs.networkingDefaults.gateway}"
    gateway = "${mydefs.networkingDefaults.gateway}"
    filter.ID_NET_NAME = "*"
  '';

  mkAnswerToml = { hostname, disks, networkConfig, bootScriptUrl, diskFilters ? [] }: pkgs.writeText "pve-answer.toml" ''
    [global]
    keyboard = "en-us"
    country = "us"
    fqdn = "${hostname}.lamhub.com"
    mailto = "lam@lamhub.com"
    timezone = "${mydefs.timeZone}"
    root_password = "changeme"
    root-ssh-keys = [ "${mydefs.mySshAuthKey}" ]

    [disk-setup]
    filesystem = "zfs"
    disk-list = [ ${concatMapStringsSep ", " (d: "\"${d}\"") disks} ]
    zfs.ashift = 12
    zfs.raid = "${if length disks > 1 then "raid1" else "raid0"}"
    ${if diskFilters != [] then concatMapStringsSep "\n" (filter: "filter.${filter.key} = \"${filter.value}\"") diskFilters else ""}

    [network]
    ${networkConfig}

    [first-boot]
    source = "from-url"
    ordering = "network-online"
    url = "${bootScriptUrl}"
  '';

  mkRestoreScript = tarballName: ''
echo "Downloading restoration config: ${tarballName}..."
wget "http://${cfg.pxeVip}/${tarballName}" -O /tmp/configs.tar.gz
if [ $? -eq 0 ]; then
    echo 'Extracting configs to temp...'
    mkdir -p /tmp/restored-configs
    tar -xzvf /tmp/configs.tar.gz -C /tmp/restored-configs
    echo 'Copying configs to system...'
    cp -rf /tmp/restored-configs/* /
    rm -rf /tmp/restored-configs
else
    echo "Failed to download config!"
fi
  '';

  mkFirstBootScript = name: restoreScript: networkConfig: pkgs.writeScript "${name}.sh" ''
#!/bin/sh
set -x
proxmox-boot-tool refresh

echo 'Writing network config...'
cat <<EOF > /etc/network/interfaces
${networkConfig}
EOF

ifreload -a

${restoreScript}
  '';

  # ============================================================================
  # Assets & Tarballs
  # ============================================================================

  proxmoxIso = pkgs.fetchurl {
    url = "https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso";
    sha256 = "228f948ae696f2448460443f4b619157cab78ee69802acc0d06761ebd4f51c3e";
  };

  ipxeUndi = "${pkgs.ipxe}/undionly.kpxe";
  ipxeEfi = "${pkgs.ipxe}/ipxe.efi";

  pve1ConfigTarball = mkConfigTarball "pve1-configs" ./configs/pve1 [];
  pve2ConfigTarball = mkConfigTarball "pve2-configs" ./configs/pve2 [];
  pveTestConfigTarball = mkConfigTarball "pve-test-configs" ./configs/pve2 [
    "./etc/pve/corosync.conf"
    "./etc/pve/storage.cfg"
  ];

  prodConfigTarballName =
    if cfg.targetHostname == mydefs.hosts.pve1.hostname then "pve1-configs.tar.gz"
    else if cfg.targetHostname == mydefs.hosts.pve2.hostname then "pve2-configs.tar.gz"
    else "custom-configs.tar.gz";

  # ============================================================================
  # Network Configuration Content
  # =============================================================================

  targetIpAddress = if cfg.targetHostname == mydefs.hosts.pve1.hostname then mydefs.hosts.pve1.ip
                    else if cfg.targetHostname == mydefs.hosts.pve2.hostname then mydefs.hosts.pve2.ip
                    else cfg.targetIp;
  testVmIpAddress = "192.168.1.35";

  networkConfigProdContent = ''
auto lo
iface lo inet loopback

auto eno1
iface eno1 inet manual

auto eno2
iface eno2 inet manual

auto eno3
iface eno3 inet manual

iface eno4 inet manual

auto bond0
iface bond0 inet manual
        bond-slaves eno1 eno2 eno3
        bond-miimon 100
        bond-mode 802.3ad
        bond-xmit-hash-policy layer3+4

auto vmbr0
iface vmbr0 inet manual
        bridge-ports eno4
        bridge-stp off
        bridge-fd 0

auto vmbr1
iface vmbr1 inet manual
        bridge-ports bond0
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 10 20 40 50

auto vmbr1.10
iface vmbr1.10 inet static
        address ${targetIpAddress}/24
        gateway ${mydefs.networkingDefaults.gateway}

auto vmbrVyos
iface vmbrVyos inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0

source /etc/network/interfaces.d/*
'';

  networkConfigTestVMContent = ''
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet manual

auto ens19
iface ens19 inet manual

auto ens20
iface ens20 inet manual

iface ens21 inet manual

auto bond0
iface bond0 inet manual
        bond-slaves ens18 ens19 ens20
        bond-miimon 100
        bond-mode active-backup
        bond-xmit-hash-policy layer3+4

auto vmbr0
iface vmbr0 inet manual
        bridge-ports ens21
        bridge-stp off
        bridge-fd 0

auto vmbr1
iface vmbr1 inet static
        address ${testVmIpAddress}/24
        gateway ${mydefs.networkingDefaults.gateway}
        bridge-ports bond0
        bridge-stp off
        bridge-fd 0

source /etc/network/interfaces.d/*
'';

  # ============================================================================
  # Boot Scripts & Answer Files
  # =============================================================================

  firstBootScriptProd = mkFirstBootScript "first-boot-prod"
    (mkRestoreScript prodConfigTarballName)
    networkConfigProdContent;

  firstBootScriptTest = mkFirstBootScript "first-boot-test"
    (mkRestoreScript "pve-test-configs.tar.gz")
    networkConfigTestVMContent;

  mkAnswer = hostname: let
    c = if hostname == mydefs.hosts.pve1.hostname then {
      disks = ["sda" "sdb"];
      ip = mydefs.hosts.pve1.ip;
      filters = [{ key = "ID_MODEL"; value = "LOGICAL VOLUME"; }];
      bootScript = "first-boot-prod.sh";
    }
    else if hostname == "testvm" then {
      disks = ["vda"];
      ip = testVmIpAddress;
      filters = [];
      bootScript = "first-boot-test.sh";
    }
    else {
      disks = ["nvme0n1"];
      ip = if hostname == mydefs.hosts.pve2.hostname then mydefs.hosts.pve2.ip else cfg.targetIp;
      filters = [];
      bootScript = "first-boot-prod.sh";
    };
  in mkAnswerToml {
    inherit hostname;
    disks = c.disks;
    diskFilters = c.filters;
    networkConfig = mkAnswerNetworkConfig c.ip;
    bootScriptUrl = "http://${cfg.pxeVip}/${c.bootScript}";
  };

  answerTomlFileProd = mkAnswer cfg.targetHostname;
  answerTomlFileTest = mkAnswer "testvm";

  # =============================================================================
  # PXE ISO & Python Server
  # =============================================================================

  pxeProxmoxFiles = let
    mkAutoInstallerToml = answerUrl: pkgs.writeText "auto-installer-mode.toml" ''
      mode = "http"
      [http]
      url = "${answerUrl}"
    '';

    activeToml = if cfg.testVM then
        mkAutoInstallerToml "http://${cfg.pxeVip}/pve-answer-test.toml"
      else
        mkAutoInstallerToml "http://${cfg.pxeVip}/pve-answer.toml";
  in pkgs.stdenv.mkDerivation {
    name = "pxe-proxmox-files";
    buildInputs = [pkgs.p7zip pkgs.cpio pkgs.zstd pkgs.gzip pkgs.xorriso];
    src = null;
    unpackPhase = "true";
    buildPhase = ''
      # 1. Create Modified ISO
      xorriso -indev ${proxmoxIso} \
        -outdev proxmox-auto.iso \
        -map ${activeToml} /auto-installer-mode.toml \
        -boot_image any keep

      # 2. Extract Components
      7z e proxmox-auto.iso boot/linux26 -so > linux26
      7z e proxmox-auto.iso boot/initrd.img -so > initrd.img

      # 3. Decompress Initrd
      mimetype="$(file --mime-type --brief initrd.img)"
      case "''${mimetype##*/}" in
        "zstd"|"x-zstd") decompress="zstd -d initrd.img -c" ;; \
        "gzip"|"x-gzip") decompress="gzip -d initrd.img -c" ;; \
        *) echo "Unknown compression"; exit 1 ;; \
      esac
      $decompress > initrd

      # 4. Wrap Modified ISO in CPIO
      ln -sf proxmox-auto.iso proxmox.iso
      echo "proxmox.iso" | cpio -L -H newc -o >> initrd
    '';
    installPhase = ''
      mkdir -p $out
      cp linux26 $out/
      cp initrd $out/
    '';
  };

  pythonPveServerScript = pkgs.writeScript "python-pve-server.py" ''
    #!${pkgs.python3.withPackages (ps: [ps.aiohttp])}/bin/python3
    import json
    import logging
    from aiohttp import web

    logging.basicConfig(level=logging.INFO)

    routes = web.RouteTableDef()

    async def serve_file(path):
        try:
            with open(path, "r") as f:
                return web.Response(text=f.read(), content_type="text/plain")
        except FileNotFoundError:
            return web.Response(status=404, text="File not found")

    @routes.post("/pve-answer.toml")
    async def pve_answer(request):
        return await serve_file("/srv/ipxe/pve-answer.toml")

    @routes.post("/pve-answer-test.toml")
    async def pve_answer_test(request):
         return await serve_file("/srv/ipxe/pve-answer-test.toml")

    app = web.Application()
    app.add_routes(routes)
    web.run_app(app, host="0.0.0.0", port=8080)
  '';

  # --- Cloud-Init ---
  ubuntuUserDataFile = pkgs.writeText "ubuntu-user-data" ''
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${cfg.targetHostname}
    username: ubuntu
    password: "$y$j9T$hhfpKDvE1InPn.kJ4KUl/.$wJkPiyEc2bYm8N2Sv8ha8glNDPlA2.pd/fythEWpat5"
  ssh:
    install-server: true
  storage:
    layout:
      name: custom
    config:
      - type: disk
        id: disk1
        match:
          size: largest
        ptable: gpt
        wipe: superblock-recursive
        grub_device: true
      - type: partition
        id: boot
        device: disk1
        size: 1G
        flag: boot
      - type: partition
        id: zfs-part
        device: disk1
        size: -1
      - type: format
        id: boot-format
        volume: boot
        fstype: fat32
      - type: zpool
        id: zpool1
        pool: rpool
        vdevs:
          - zfs-part
        properties:
          ashift: 12
        mountpoint: none
        bootfs: rpool/ROOT/ubuntu
      - type: zfs
        id: zfs-root
        pool: rpool
        volume: ROOT/ubuntu
        mountpoint: "/"
        properties:
          canmount: on
      - type: zfs
        id: zfs-home
        pool: rpool
        volume: ROOT/home
        properties:
          mountpoint: /home
      - type: zfs
        id: zfs-data
        pool: rpool
        volume: ROOT/data
        properties:
          mountpoint: /data
      - type: mount
        id: boot-mount
        device: boot-format
        path: /boot/efi
  network:
    version: 2
    ethernets:
      any:
        dhcp4: true
        nameservers:
          addresses: [1.1.1.1, 8.8.8.8]
  packages:
    - openssh-server
    - cloud-init
    - curtin
    - zfsutils-linux
  late-commands:
    - wget http://${cfg.pxeVip}/post-install.sh -O /target/root/post-install.sh
    - chmod +x /target/root/post-install.sh
    - chroot /target /root/post-install.sh
'';

in {
  options.modules.os.linux.services.pxe-ipxe = {
    enable = mkEnableOption "Proxmox iPXE installer service";

    testVM = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Test VM mode (uses separate safe config, DHCP).";
    };

    pxeVip = mkOption {
      type = types.str;
      description = "PXE virtual IP address.";
    };
    targetHostname = mkOption {
      type = types.str;
      description = "Hostname of the target machine.";
    };
    targetIp = mkOption {
      type = types.str;
      description = "IP address of the target machine.";
    };
  };

  config = mkIf cfg.enable {
    environment = {
      systemPackages = [pkgs.wget];
      etc = {
        "autoexec-script" = {
          text = ''
            #!ipxe
            dhcp
            menu PXE Boot Menu
            item proxmox Setup Proxmox (Manual)
            item proxmox-auto Setup Proxmox (Auto-Install)
            item proxmox-auto-debug Setup Proxmox (Auto-Install Debug)
            item ubuntu Setup Ubuntu (cloud-init)
            choose target && goto ''${target}

            :proxmox
            kernel http://${cfg.pxeVip}/proxmox/linux26 intel_iommu=on iommu=pt \
              vga=791 video=vesafb:ywrap,mtrr ramdisk_size=2097152 rw quiet splash=silent
            initrd http://${cfg.pxeVip}/proxmox/initrd
            boot
            goto end

            :proxmox-auto
            kernel http://${cfg.pxeVip}/proxmox/linux26 intel_iommu=on iommu=pt \
              vga=791 video=vesafb:ywrap,mtrr ramdisk_size=2097152 rw quiet splash=silent \
              proxmox-start-auto-installer
            initrd http://${cfg.pxeVip}/proxmox/initrd
            boot
            goto end

            :proxmox-auto-debug
            kernel http://${cfg.pxeVip}/proxmox/linux26 intel_iommu=on iommu=pt \
              vga=791 video=vesafb:ywrap,mtrr ramdisk_size=2097152 rw quiet splash=silent \
              proxmox-start-auto-installer proxdebug
            initrd http://${cfg.pxeVip}/proxmox/initrd
            boot
            goto end

            :ubuntu
            kernel http://192.168.1.6:8080/ISO/_legacy/Ubuntu/live/vmlinuz \
              ip=dhcp nameserver=1.1.1.1 \
              url=http://192.168.1.6:8080/ISO/_legacy/Ubuntu/live/ubuntu-24.04.3-live-server-amd64.iso \
              autoinstall ds=nocloud-net;s=http://${cfg.pxeVip}/cloud-init/ \
              cloud-config-url=/dev/null
            initrd http://192.168.1.6:8080/ISO/_legacy/Ubuntu/live/initrd
            boot
            goto end
          '';
        };
        "ubuntu-user-data" = {
          target = "srv/ipxe/ubuntu-user-data";
          text = builtins.readFile ubuntuUserDataFile;
        };
        "post-install.sh" = {
          target = "srv/ipxe/post-install.sh";
          text = ''
            #!/bin/bash
            curl -fsSL https://deb.debian.org/debian/archive-keyring.pgp | gpg --dearmor -o /usr/share/keyrings/ubuntu-archive-keyring.gpg
            apt update && apt install -y postfix
            update-grub
          '';
          mode = "0755";
        };
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."pxe.local" = {
        listen = [
          {
            addr = cfg.pxeVip;
            port = 80;
          }
        ];
        root = "/srv/ipxe";
        locations."/pve-answer.toml" = {
          proxyPass = "http://127.0.0.1:8080/pve-answer.toml";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Content-Type $http_content_type;
            proxy_method POST;
          '';
        };
        locations."/pve-answer-test.toml" = {
          proxyPass = "http://127.0.0.1:8080/pve-answer-test.toml";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Content-Type $http_content_type;
            proxy_method POST;
          '';
        };
      };
    };

    systemd.services.python-pve-server = {
      description = "Python PVE Answer Server";
      wantedBy = ["multi-user.target"];
      requires = ["network-online.target"];
      after = ["network-online.target"];
      serviceConfig = {
        ExecStart = "${pythonPveServerScript}";
        Restart = "always";
      };
    };

    services.atftpd = {
      enable = true;
      root = "/var/lib/tftpboot";
    };

    modules.os.linux.services.refind-booter.enable = true;

    networking.firewall.allowedUDPPorts = [69]; # tftp
    networking.firewall.allowedTCPPorts = [80 8006 8080]; # http, proxmox gui, python server

    systemd.services.populate-ipxe-assets = {
      description = "Populate iPXE assets";
      wantedBy = ["multi-user.target"];
      requires = ["network-online.target"];
      after = ["network-online.target"];
      script = ''
        # Populate iPXE assets
        mkdir -p /var/lib/tftpboot/ipxe
        cp ${ipxeUndi} /var/lib/tftpboot/ipxe/undionly.kpxe
        cp ${ipxeEfi} /var/lib/tftpboot/ipxe/ipxe.efi
        cp ${config.environment.etc."autoexec-script".source} /var/lib/tftpboot/autoexec.ipxe

        # Populate Proxmox assets
        mkdir -p /srv/ipxe/proxmox
        ln -sf ${pxeProxmoxFiles}/linux26 /srv/ipxe/proxmox/linux26
        ln -sf ${pxeProxmoxFiles}/initrd /srv/ipxe/proxmox/initrd

        # Copy answer files
        cp ${answerTomlFileProd} /srv/ipxe/pve-answer.toml
        cp ${answerTomlFileTest} /srv/ipxe/pve-answer-test.toml

        # Copy boot scripts
        cp ${firstBootScriptProd} /srv/ipxe/first-boot-prod.sh
        cp ${firstBootScriptTest} /srv/ipxe/first-boot-test.sh

        # Copy configuration tarballs
        cp ${pve1ConfigTarball} /srv/ipxe/pve1-configs.tar.gz
        cp ${pve2ConfigTarball} /srv/ipxe/pve2-configs.tar.gz
        cp ${pveTestConfigTarball} /srv/ipxe/pve-test-configs.tar.gz

        # Populate cloud-init assets
        mkdir -p /srv/ipxe/cloud-init
        cp ${config.environment.etc."ubuntu-user-data".source} /srv/ipxe/cloud-init/user-data
        echo "instance-id: ubuntu-install-$(date +%s)" > /srv/ipxe/cloud-init/meta-data
      '';
      serviceConfig.Type = "oneshot";
    };
  };
}
