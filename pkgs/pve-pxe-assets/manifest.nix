{ pkgs, lib, ... }:
# Generate a manifest.json containing build-time checksums of the compiled assets
{
  targetName,
  hostname,
  bootFiles,
  templates,
  restoreTarball,
  firstBootScript,
}:
pkgs.runCommand "manifest.json"
  {
    inherit targetName hostname;
    bootLinux = "${bootFiles}/linux26";
    bootInitrd = "${bootFiles}/initrd";
    firstBoot = "${firstBootScript}";
    restoreTar = "${restoreTarball}";
  }
  ''
    # compute hashes
    hash_linux=$(sha256sum $bootLinux | awk '{print $1}')
    hash_initrd=$(sha256sum $bootInitrd | awk '{print $1}')
    hash_firstboot=$(sha256sum $firstBoot | awk '{print $1}')
    hash_restore=$(sha256sum $restoreTar | awk '{print $1}')

    # output JSON
    cat <<EOF > $out
    {
      "schemaVersion": "1.0.0",
      "targetName": "$targetName",
      "expectedHostname": "$hostname",
      "firstBootProtocolVersion": "1.0.0",
      "artifacts": {
        "linux26": {
          "path": "proxmox/linux26",
          "sha256": "$hash_linux"
        },
        "initrd": {
          "path": "proxmox/initrd",
          "sha256": "$hash_initrd"
        },
        "firstBootScript": {
          "path": "first-boot-$hostname.sh",
          "sha256": "$hash_firstboot"
        },
        "restoreTarball": {
          "path": "$hostname-configs.tar.gz",
          "sha256": "$hash_restore"
        }
      }
    }
    EOF
  ''
