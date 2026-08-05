{
  pkgs,
  mydefs,
  ...
}:
let
  substituteTemplate =
    {
      name,
      template,
      replacements,
    }:
    let
      replacementsJson = pkgs.writeText "replacements-${name}.json" (builtins.toJSON replacements);
    in
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 - ${template} ${replacementsJson} $out <<'PY'
      import json
      import sys

      template_path, replacements_path, output_path = sys.argv[1:]
      with open(template_path) as source:
          content = source.read()
      with open(replacements_path) as source:
          replacements = json.load(source)
      for placeholder, value in replacements.items():
          content = content.replace(placeholder, str(value))
      with open(output_path, "w") as output:
          output.write(content)
      PY
    '';
  configTarball =
    { name, src }:
    pkgs.runCommand "${name}.tar.gz"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        tar --owner=0 --group=0 --numeric-owner --sort=name --mtime="@0" \
          -czvf $out -C ${src} .
      '';
  pveStateRoot = ../../infra/proxmox/state/pve;

  # Cached base files from downloaded Proxmox ISO (public enterprise CDN pin).
  proxmoxIso = pkgs.fetchurl {
    url = "https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso";
    sha256 = "0v1cxxrrb1zkvgiixyra6g9i9iq7mb4j8pqp99i2gdgrdm0zx22f";
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
    {
      target,
      bootstrapIp,
      autoBoot ? false,
      serialConsole ? false,
    }:
    let
      stateDir = pveStateRoot + "/${target}";
      targetDir = ../../infra/proxmox/pxe/targets + "/${target}";
      answerTemplate = targetDir + "/answer.toml";

      # 1. Package only the reviewed, per-node host-local state. Cluster-wide
      # pmxcfs state is deliberately excluded from normal installation.
      configDir = pkgs.runCommand "${target}-configs-dir" { } ''
        test -d ${stateDir}
        test -f ${answerTemplate}
        mkdir -p $out
        cp -rT ${stateDir}/ $out/
        chmod -R u+w $out
        test -f $out/etc/network/interfaces
        if [ "${target}" != pve-test ]; then
          test -f $out/etc/default/grub
          test -f $out/etc/kernel/cmdline
          test -f $out/etc/modprobe.d/zfs.conf
        fi
        if [ -e $out/etc/pve ]; then
          echo "normal PVE install state must not contain /etc/pve" >&2
          exit 1
        fi
      '';

      # 2. Config Tarball (cheap, target-specific)
      restoreTarball = configTarball {
        name = "${target}-configs";
        src = configDir;
      };

      # Write first-boot script template and inject sha256 checksum at build time
      firstBootScriptWithHash =
        pkgs.runCommand "first-boot-${target}.sh"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            template = ../../infra/proxmox/pxe/templates/first-boot.sh;
            restoreTarballPath = "${restoreTarball}";
            bootstrapUrl = "http://${bootstrapIp}";
            tarballName = "${target}-configs.tar.gz";
            dontPatchShebangs = true;
          }
          ''
            hash_tarball=$(sha256sum $restoreTarballPath | awk '{print $1}')

            python3 -c "
            with open('$template', 'r') as f:
                content = f.read()
            content = content.replace('@RESTORE_TARBALL_NAME@', '$tarballName')
            content = content.replace('@RESTORE_TARBALL_HASH@', '$hash_tarball')
            content = content.replace('@BOOTSTRAP_URL@', '$bootstrapUrl')
            with open('$out', 'w') as f:
                f.write(content)
            "
          '';

      # Render iPXE menu
      autoexecIpxe = substituteTemplate {
        name = "autoexec-${target}.ipxe";
        template = ../../infra/proxmox/pxe/templates/autoexec.ipxe;
        replacements = {
          "@HOSTNAME@" = target;
          "@BOOTSTRAP_IP@" = bootstrapIp;
          "@BOOT_SELECTION@" = if autoBoot then "set target proxmox-auto" else "choose target";
          "@CONSOLE_ARGS@" = if serialConsole then "console=tty0 console=ttyS0,115200n8" else "";
        };
      };

      # Render non-secret answer file template
      answerTomlNonsecret = substituteTemplate {
        name = "answer-nonsecret-${target}.toml";
        template = answerTemplate;
        replacements = {
          "@TIMEZONE@" = mydefs.timeZone;
          "@SSH_PUBKEY@" = mydefs.mySshAuthKey;
          "@FIRST_BOOT_URL@" = "http://${bootstrapIp}/first-boot-${target}.sh";
        };
      };

      # 3. Custom target-specific initrd
      pxeProxmoxFilesTarget = pkgs.stdenv.mkDerivation {
        name = "pxe-proxmox-files-${target}";
        buildInputs = [
          pkgs.xorriso
          pkgs.cpio
          pkgs.zstd
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

          # Serve one compressed initramfs, as the upstream ISO does. Keeping
          # the expanded base archive plus the embedded ISO uncompressed makes
          # the PVE 9.2 payload exceed the reliable iPXE contiguous-load margin.
          zstd -T0 -3 initrd -o initrd.zst
          mv initrd.zst initrd
        '';
        installPhase = ''
          mkdir -p $out
          cp ${proxmoxBaseFiles}/linux26 $out/
          cp initrd $out/
        '';
      };

      # 4. Manifest generation
      manifestJson = pkgs.runCommand "manifest.json" { } ''
        hash() { sha256sum "$1" | awk '{print $1}'; }
        cat > $out <<EOF
        {
          "schemaVersion": "1.0.0",
          "targetName": "${target}",
          "expectedHostname": "${target}",
          "firstBootProtocolVersion": "1.0.0",
          "artifacts": {
            "linux26": { "path": "proxmox/linux26", "sha256": "$(hash ${pxeProxmoxFilesTarget}/linux26)" },
            "initrd": { "path": "proxmox/initrd", "sha256": "$(hash ${pxeProxmoxFilesTarget}/initrd)" },
            "ipxeUndionly": { "path": "ipxe/undionly.kpxe", "sha256": "$(hash ${ipxeUndi})" },
            "ipxeEfi": { "path": "ipxe/ipxe.efi", "sha256": "$(hash ${ipxeEfi})" },
            "autoexec": { "path": "autoexec.ipxe", "sha256": "$(hash ${autoexecIpxe})" },
            "answerTemplate": { "path": "pve-answer-nonsecret.toml", "sha256": "$(hash ${answerTomlNonsecret})" },
            "firstBootScript": { "path": "first-boot-${target}.sh", "sha256": "$(hash ${firstBootScriptWithHash})" },
            "restoreTarball": { "path": "${target}-configs.tar.gz", "sha256": "$(hash ${restoreTarball})" }
          }
        }
        EOF
      '';

    in
    pkgs.stdenv.mkDerivation {
      name = "pve-pxe-assets-${target}";
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

        cp ${firstBootScriptWithHash} $out/first-boot-${target}.sh
        cp ${restoreTarball} $out/${target}-configs.tar.gz
        cp ${answerTomlNonsecret} $out/pve-answer-nonsecret.toml
        cp ${manifestJson} $out/manifest.json
      '';
    };

  defaultDrv = mkPvePxeAssets {
    target = "pve-test";
    bootstrapIp = "192.168.250.1";
    autoBoot = true;
  };
in
defaultDrv.overrideAttrs (old: {
  passthru = {
    inherit mkPvePxeAssets;
  };
})
