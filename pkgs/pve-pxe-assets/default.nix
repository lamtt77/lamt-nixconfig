{
  pkgs,
  lib,
  mydefs,
  ...
}:
let
  targets = import ./targets.nix mydefs;

  substituteTemplate = import ./lib/substitute-template.nix { inherit pkgs lib; };
  configTarball = import ./lib/config-tarball.nix { inherit pkgs lib; };
  manifestGen = import ./manifest.nix { inherit pkgs lib; };

  # Cached base files from downloaded Proxmox ISO
  proxmoxIso = pkgs.fetchurl {
    url = "https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso";
    sha256 = "228f948ae696f2448460443f4b619157cab78ee69802acc0d06761ebd4f51c3e";
  };

  # Extract base kernel/initrd and decompress base initrd (expensive, target-independent)
  proxmoxBaseFiles = pkgs.stdenv.mkDerivation {
    name = "proxmox-base-files";
    buildInputs = [
      pkgs.p7zip
      pkgs.cpio
      pkgs.zstd
      pkgs.gzip
      pkgs.file
    ];
    src = null;
    unpackPhase = "true";
    buildPhase = ''
      # Extract components from downloaded ISO
      7z e ${proxmoxIso} boot/linux26 -so > linux26
      7z e ${proxmoxIso} boot/initrd.img -so > initrd.img

      # Decompress base initrd
      mimetype="$(file --mime-type --brief initrd.img)"
      case "''${mimetype##*/}" in
        "zstd"|"x-zstd") decompress="zstd -d initrd.img -c" ;; \
        "gzip"|"x-gzip") decompress="gzip -d initrd.img -c" ;; \
        *) echo "Unknown compression"; exit 1 ;; \
      esac
      $decompress > initrd
    '';
    installPhase = ''
      mkdir -p $out
      cp linux26 $out/
      cp initrd $out/
      cp ${proxmoxIso} $out/proxmox-base.iso
    '';
  };

  ipxeUndi = "${pkgs.ipxe}/undionly.kpxe";
  ipxeEfi = "${pkgs.ipxe}/ipxe.efi";

  mkPvePxeAssets =
    { target, bootstrapIp }:
    let
      targetCfg = targets.${target} or (throw "Unknown PXE target: ${target}");

      renderedCorosync = substituteTemplate {
        name = "corosync-${targetCfg.hostname}.conf";
        template = ./templates/corosync.conf;
        replacements = {
          "@NODE1_NAME@" = targets.pve1.proxmoxNode;
          "@NODE1_IP@" = mydefs.hosts.pve1.ip;
          "@NODE2_NAME@" = targets.pve2.proxmoxNode;
          "@NODE2_IP@" = mydefs.hosts.pve2.ip;
          "@CLUSTER_NAME@" = "barcluster";
          "@CONFIG_VERSION@" = "2";
        };
      };

      renderedStorage = substituteTemplate {
        name = "storage-${targetCfg.hostname}.cfg";
        template = ./templates/storage.cfg;
        replacements = {
          "@NFS_VM_EXPORT@" = "/mnt/arthur_z2/VM";
          "@NFS_ISO_EXPORT@" = "/mnt/arthur_z2/Boot/ISO";
          "@NAS_IP@" = mydefs.nasIp;
        };
      };

      # 1. Config Directory (combining static and dynamically rendered files)
      configDir = pkgs.runCommand "${targetCfg.hostname}-configs-dir" { } ''
        mkdir -p $out
        if [ -d ${./configs + "/${target}"} ]; then
          cp -rT ${./configs + "/${target}"}/ $out/
          chmod -R u+w $out
        fi
        ${lib.optionalString targetCfg.includeClusterStorage ''
          mkdir -p $out/etc/pve
          cp ${renderedCorosync} $out/etc/pve/corosync.conf
          cp ${renderedStorage} $out/etc/pve/storage.cfg
        ''}
      '';

      # 2. Config Tarball (cheap, target-specific)
      restoreTarball = configTarball {
        name = "${targetCfg.hostname}-configs";
        src = configDir;
      };

      # 2. Render templates (cheap, target-specific)
      networkInterfaces = substituteTemplate {
        name = "network-interfaces-${targetCfg.hostname}";
        template = ./templates + "/${targetCfg.networkTemplate}";
        replacements = {
          "@FINAL_IP@" = targetCfg.finalIp;
          "@NETMASK@" = targetCfg.netmask;
          "@GATEWAY@" = targetCfg.gateway;
        };
      };

      # Write first-boot script template and inject sha256 checksum at build time
      firstBootScriptWithHash =
        pkgs.runCommand "first-boot-${targetCfg.hostname}.sh"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            template = ./templates/first-boot.sh;
            restoreTarballPath = "${restoreTarball}";
            networkInterfacesPath = "${networkInterfaces}";
            bootstrapUrl = "http://${bootstrapIp}";
            tarballName = "${targetCfg.hostname}-configs.tar.gz";
            dontPatchShebangs = true;
          }
          ''
            hash_tarball=$(sha256sum $restoreTarballPath | awk '{print $1}')

            python3 -c "
            with open('$template', 'r') as f:
                content = f.read()
            with open('$networkInterfacesPath', 'r') as f:
                net_content = f.read()
            content = content.replace('@RESTORE_TARBALL_NAME@', '$tarballName')
            content = content.replace('@RESTORE_TARBALL_HASH@', '$hash_tarball')
            content = content.replace('@BOOTSTRAP_URL@', '$bootstrapUrl')
            content = content.replace('@NETWORK_INTERFACES@', net_content)
            with open('$out', 'w') as f:
                f.write(content)
            "
          '';

      # Render iPXE menu
      autoexecIpxe = substituteTemplate {
        name = "autoexec-${targetCfg.hostname}.ipxe";
        template = ./templates/autoexec.ipxe;
        replacements = {
          "@HOSTNAME@" = targetCfg.hostname;
          "@BOOTSTRAP_IP@" = bootstrapIp;
          "@BOOT_SELECTION@" =
            if targetCfg.autoBoot or false then "set target proxmox-auto" else "choose target";
          "@CONSOLE_ARGS@" =
            if targetCfg.serialConsole or false then "console=tty0 console=ttyS0,115200n8" else "";
        };
      };

      # Render non-secret answer file template
      answerTomlNonsecret = substituteTemplate {
        name = "answer-nonsecret-${targetCfg.hostname}.toml";
        template = ./templates/answer.toml;
        replacements = {
          "@HOSTNAME@" = targetCfg.hostname;
          "@TIMEZONE@" = mydefs.timeZone;
          "@SSH_PUBKEY@" = mydefs.mySshAuthKey;
          "@DISK_LIST@" = lib.concatMapStringsSep ", " (d: "\"${d}\"") targetCfg.disks;
          "@ZFS_RAID@" = if lib.length targetCfg.disks > 1 then "raid1" else "raid0";
          "@DISK_FILTERS@" =
            if targetCfg.diskFilters != [ ] then
              lib.concatMapStringsSep "\n" (
                filter: "filter.${filter.key} = \"${filter.value}\""
              ) targetCfg.diskFilters
            else
              "";
          "@NETWORK_CONFIG@" =
            if (targetCfg.installerNetworkSource or "from-answer") == "from-dhcp" then
              ''source = "from-dhcp"''
            else
              ''
                source = "from-answer"
                cidr = "${targetCfg.finalIp}/${targetCfg.netmask}"
                dns = "${targetCfg.gateway}"
                gateway = "${targetCfg.gateway}"
                filter.ID_NET_NAME = "*"
              '';
          "@FIRST_BOOT_URL@" = "http://${bootstrapIp}/first-boot-${targetCfg.hostname}.sh";
        };
      };

      # 3. Custom target-specific initrd
      pxeProxmoxFilesTarget = pkgs.stdenv.mkDerivation {
        name = "pxe-proxmox-files-${targetCfg.hostname}";
        buildInputs = [
          pkgs.xorriso
          pkgs.cpio
        ];
        src = null;
        unpackPhase = "true";
        buildPhase = ''
          cat <<EOF > auto-installer-mode.toml
          mode = "http"
          [http]
          url = "http://${bootstrapIp}/pve-answer.toml"
          EOF

          # Custom auto ISO
          xorriso -indev ${proxmoxBaseFiles}/proxmox-base.iso \
            -outdev proxmox-auto.iso \
            -map auto-installer-mode.toml /auto-installer-mode.toml \
            -boot_image any keep

          cp ${proxmoxBaseFiles}/initrd initrd
          chmod +w initrd
          ln -sf proxmox-auto.iso proxmox.iso
          echo "proxmox.iso" | cpio -L -H newc -o >> initrd
        '';
        installPhase = ''
          mkdir -p $out
          cp ${proxmoxBaseFiles}/linux26 $out/
          cp initrd $out/
        '';
      };

      # 4. Manifest generation
      manifestJson = manifestGen {
        targetName = target;
        hostname = targetCfg.hostname;
        bootFiles = pxeProxmoxFilesTarget;
        templates = null;
        restoreTarball = restoreTarball;
        firstBootScript = firstBootScriptWithHash;
      };

    in
    pkgs.stdenv.mkDerivation {
      name = "pve-pxe-assets-${targetCfg.hostname}";
      src = null;
      unpackPhase = "true";
      installPhase = ''
        mkdir -p $out/ipxe
        cp ${ipxeUndi} $out/ipxe/undionly.kpxe
        cp ${ipxeEfi} $out/ipxe/ipxe.efi
        cp ${autoexecIpxe} $out/autoexec.ipxe

        mkdir -p $out/proxmox
        ln -sf ${pxeProxmoxFilesTarget}/linux26 $out/proxmox/linux26
        ln -sf ${pxeProxmoxFilesTarget}/initrd $out/proxmox/initrd

        cp ${firstBootScriptWithHash} $out/first-boot-${targetCfg.hostname}.sh
        cp ${restoreTarball} $out/${targetCfg.hostname}-configs.tar.gz
        cp ${answerTomlNonsecret} $out/pve-answer-nonsecret.toml
        cp ${manifestJson} $out/manifest.json
      '';
    };

  defaultDrv = mkPvePxeAssets {
    target = "pve-test";
    bootstrapIp = "192.168.250.1";
  };
in
defaultDrv.overrideAttrs (old: {
  passthru = {
    inherit mkPvePxeAssets;
  };
})
