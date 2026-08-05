{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  bootstrapIp = "192.168.0.5";
  pve1Assets = pkgs.pve-pxe-assets.mkPvePxeAssets {
    target = "pve1";
    inherit bootstrapIp;
  };
  pve2Assets = pkgs.pve-pxe-assets.mkPvePxeAssets {
    target = "pve2";
    inherit bootstrapIp;
  };
  mkBootstrapPlan =
    target:
    pkgs.writeText "bootstrap-plan-${target}.json" (
      builtins.toJSON {
        apiVersion = "nxd.dev/v1alpha1";
        kind = "BootstrapPlan";
        metadata.name = "${target}-cold-recovery";
        spec = {
          inherit target;
          interface = "eth0";
          listenIp = bootstrapIp;
          dhcpRange = "192.168.0.200,192.168.0.220";
          assetsDir = "/etc/cold-recovery/assets/${target}";
          mode = "isolated";
          workdir = "/run/nxd-bootstrap-${target}";
          allowGeneratedCredential = true;
          timeoutSeconds = 7200;
          dnsmasqPath = "${pkgs.dnsmasq}/bin/dnsmasq";
          ipPath = "${pkgs.iproute2}/bin/ip";
        };
      }
    );
in
{
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  boot.kernelParams = [ "net.ifnames=0" ];
  nix.settings.experimental-features = "nix-command flakes";

  environment.systemPackages = [
    pkgs.dnsmasq
    pkgs.git
    pkgs.iproute2
    pkgs.nxd
    pkgs.vim
  ];

  environment.etc = {
    "cold-recovery/assets/pve1".source = pve1Assets;
    "cold-recovery/assets/pve2".source = pve2Assets;
    "cold-recovery/plans/pve1.json".source = mkBootstrapPlan "pve1";
    "cold-recovery/plans/pve2.json".source = mkBootstrapPlan "pve2";
    "cold-recovery/README".text = ''
      Cold recovery bootstrap IP: ${bootstrapIp}

      Break-glass local service adapter (normal recovery uses reviewed
      `nxd plan ... --intent recovery` and `nxd apply`):
        sudo nxd-provider-pve bootstrap-serve /etc/cold-recovery/plans/pve1.json

      Use /etc/cold-recovery/plans/pve2.json when recovering pve2.
      The generated installer password is available only in the root-readable
      answer file path printed by NXD and is removed when NXD exits.
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
