# Build bootable rEFInd USB image for chainloading EFI on NVMe
# Usage:
#   1. Build the image: nix build '.#nixosConfigurations.<host>.config.system.build.refindBootImg'
#   2. Flash to USB (replace X with your USB device number, check with lsblk/diskutil):
#      - Linux: sudo dd if=result of=/dev/sdX bs=1M status=progress
#      - macOS:
#           diskutil list
#           diskutil unmountDisk /dev/diskN
#           sudo dd if=refind-booter.img of=/dev/rdiskN bs=1M conv=fsync
#           diskutil eject /dev/diskN
{
  package ? null,
  drivers ? [ "NvmExpressDxe.efi" ],
  extraConfig ? "",
  imageSize ? 64,
}:
{
  lib,
  pkgs,
  ...
}:
let
  effectivePackage = if package == null then pkgs.refind else package;
  cloverIso7z = pkgs.fetchurl {
    url = "https://github.com/CloverHackyColor/CloverBootloader/releases/download/5164/Clover-5164-X64.iso.7z";
    sha256 = "0309s2r61b4xmz42vjqc0jykwqkgh81nsb5crjxfzfqf8lva7q6d";
  };

  nvmeDriver = pkgs.runCommand "nvme-driver" { nativeBuildInputs = [ pkgs.p7zip ]; } ''
    # Extract the 7z to get the iso
    7z e ${cloverIso7z} -o. > /dev/null
    # Assume the iso is Clover-5164-X64.iso
    7z e Clover-5164-X64.iso EFI/CLOVER/drivers/off/NvmExpressDxe.efi -o. > /dev/null
    cp NvmExpressDxe.efi $out
  '';

  # 1. Create the refind.conf file
  refindConf = pkgs.writeText "refind.conf" ''
    # Wait 5 seconds before auto-booting
    timeout 5

    # Set the default boot entry to the first one (NVMe drive)
    default_selection 1

    # Scan for all internal and external drives
    scanfor internal,external

    # The filesystem label we will create
    dont_scan_volumes "REFIND_BOOT"

    # Add any user-defined custom options
    ${extraConfig}
  '';
in
{
  system.build.refindBootImg =
    let
      # Derivation 1: The Boot Directory
      bootDir =
        let
          refindEfiDir = "${effectivePackage}/share/refind";
        in
        pkgs.runCommand "refind-booter-dir"
          {
            driversList = lib.concatStringsSep " " drivers;
          }
          ''
              mkdir -p $out/EFI/BOOT
              mkdir -p $out/EFI/BOOT/drivers_x64
              cp ${refindEfiDir}/refind_x64.efi $out/EFI/BOOT/bootx64.efi
              cp ${refindConf} $out/EFI/BOOT/refind.conf
            for driver in $driversList; do
              if [ "$driver" = "NvmExpressDxe.efi" ]; then
                cp ${nvmeDriver} "$out/EFI/BOOT/drivers_x64/$driver"
              else
                cp "${refindEfiDir}/drivers_x64/$driver" "$out/EFI/BOOT/drivers_x64/"
              fi
            done
          '';

      # Derivation 2: The Boot Image
      bootImg =
        pkgs.runCommand "refind-booter.img"
          {
            # We need these tools to build the image
            nativeBuildInputs = [
              pkgs.dosfstools
              pkgs.mtools
            ];
          }
          ''
            echo "Creating ${toString imageSize}MB bootable FAT32 image..."
            dd if=/dev/zero of=$out bs=1M count=${toString imageSize}

            # Format the image file as FAT32 with the required label
            mkfs.vfat -F32 -n "REFIND_BOOT" $out

            echo "Copying EFI files to image..."
            # Use mcopy to copy the EFI directory from our first derivation
            # into the root of the new .img file.
            mcopy -s -i $out -v ${bootDir}/EFI ::/EFI

            echo "Image created: $out"
          '';
    in
    bootImg;
}
