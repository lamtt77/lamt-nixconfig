{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  bootstrapIp = "192.168.0.5";
  installer = pkgs.callPackage ../../pkgs/installer-rs { };
  pve1Assets = pkgs.pve-pxe-assets.mkPvePxeAssets {
    target = "pve1";
    inherit bootstrapIp;
  };
  pve2Assets = pkgs.pve-pxe-assets.mkPvePxeAssets {
    target = "pve2";
    inherit bootstrapIp;
  };
in
{
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  boot.kernelParams = [ "net.ifnames=0" ];
  nix.settings.experimental-features = "nix-command flakes";

  environment.systemPackages = [
    installer
    pkgs.dnsmasq
    pkgs.git
    pkgs.iproute2
    pkgs.pve-answer-server
    pkgs.vim
  ];

  environment.etc = {
    "cold-recovery/assets/pve1".source = pve1Assets;
    "cold-recovery/assets/pve2".source = pve2Assets;
    "cold-recovery/README".text = ''
      Cold recovery bootstrap IP: ${bootstrapIp}

      Example:
        sudo pve-bootstrap-server \
          --target pve1 \
          --interface eth0 \
          --listen-ip ${bootstrapIp} \
          --dhcp-range 192.168.0.200,192.168.0.220 \
          --assets-dir /etc/cold-recovery/assets/pve1

      Replace pve1 with pve2 and use the matching assets directory when
      recovering the Dell R720.
    '';
  };

  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [
    (import ../../defines.nix).mySshAuthKey
  ];

  system.build.coldRecoveryImg = pkgs.runCommand "cold-recovery.iso" { } ''
    iso_path=$(echo ${config.system.build.isoImage}/iso/*.iso)
    ln -s "$iso_path" "$out"
  '';

  assertions = [
    {
      assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
      message = "The Cold Recovery USB image is supported only on x86_64-linux.";
    }
  ];

  isoImage.volumeID = lib.mkForce "PVE_COLD_RECOVERY";
}
