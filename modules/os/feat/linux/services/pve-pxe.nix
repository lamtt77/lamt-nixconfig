{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.os.linux.services.pve-pxe;
  planFile = pkgs.writeText "bootstrap-plan.json" (
    builtins.toJSON {
      apiVersion = "nxd.dev/v1alpha1";
      kind = "BootstrapPlan";
      metadata = {
        name = "pve-bootstrap";
      };
      spec = {
        target = cfg.target;
        interface = cfg.interface;
        listenIp = cfg.listenAddress;
        dhcpRange = if cfg.dhcpBackend == "dnsmasq" then cfg.dhcpRange else null;
        assetsDir = "${cfg.assets}";
        mode = if cfg.dhcpBackend == "dnsmasq" then "isolated" else "external";
        workdir = "/run/nxd-pve-bootstrap/session";
        allowGeneratedCredential = cfg.allowGeneratedCredential;
        timeoutSeconds = cfg.timeoutSeconds;
        dnsmasqPath = "${pkgs.dnsmasq}/bin/dnsmasq";
        ipPath = "${pkgs.iproute2}/bin/ip";
      };
    }
  );
in
{
  options.modules.os.linux.services.pve-pxe = {
    target = mkOption {
      type = types.str;
      description = "PXE target identity; must match the selected asset manifest.";
    };

    assets = mkOption {
      type = types.package;
      description = "Target-specific pure PXE assets package built by mkPvePxeAssets.";
    };

    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Interface to bind the PXE services to.";
    };

    listenAddress = mkOption {
      type = types.str;
      description = "Listen IP address for HTTP and TFTP services.";
    };

    dhcpBackend = mkOption {
      type = types.enum [
        "none"
        "dnsmasq"
      ];
      default = "none";
      description = ''
        DHCP/TFTP backend to use:
        - "none": Another DHCP daemon (e.g. Kea) owns IP leasing and PXE options; TFTP runs via dnsmasq (external mode).
        - "dnsmasq": dnsmasq runs on the interface, providing isolated DHCP/TFTP.
      '';
    };

    dhcpRange = mkOption {
      type = types.str;
      default = "192.168.250.100,192.168.250.150";
      description = "DHCP allocation range in start,end form for isolated mode.";
    };

    passwordSecretName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOPS secret name containing the temporary installer root password.";
    };

    allowGeneratedCredential = mkOption {
      type = types.bool;
      default = false;
      description = "Allow an ephemeral generated installer password; intended only for portable/disposable recovery.";
    };

    timeoutSeconds = mkOption {
      type = types.ints.between 1 86400;
      default = 7200;
      description = "Maximum duration of one bounded bootstrap service run.";
    };

    vrrpControlled = mkOption {
      type = types.bool;
      default = false;
      description = "Whether service lifecycle is managed by VRRP state transitions.";
    };
  };

  config = mkIf (cfg.interface != null) {
    # Assertions to prevent invalid/unsafe runtime combinations
    assertions = [
      {
        assertion =
          !(
            config.services.kea.dhcp4.enable
            && cfg.dhcpBackend == "dnsmasq"
            && builtins.elem cfg.interface (
              config.services.kea.dhcp4.settings.interfaces-config.interfaces or [ ]
            )
          );
        message = "Cannot run dnsmasq DHCP backend alongside active production Kea DHCP on the same interface.";
      }
      {
        assertion = cfg.listenAddress != "";
        message = "PXE bootstrap listenAddress must be specified.";
      }
      {
        assertion = cfg.passwordSecretName != null || cfg.allowGeneratedCredential;
        message = "PXE bootstrap requires passwordSecretName unless generated credentials are explicitly allowed.";
      }
    ];

    # SOPS secret reference for systemd credential binding
    sops.secrets = mkIf (cfg.passwordSecretName != null) {
      "${cfg.passwordSecretName}" = { };
    };

    # Bounded PXE / Answer service via the PVE provider-owned bootstrap adapter.
    # Implementation lives in nxd-provider-pve (not nxd-core / not the public CLI).
    systemd.services.nxd-pve-bootstrap = {
      description = "NXD PVE Provider PXE Bootstrap Server";
      wantedBy = if cfg.vrrpControlled then [ ] else [ "multi-user.target" ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      path = [
        pkgs.dnsmasq
        pkgs.iproute2
      ];

      # Load SOPS secret into systemd credential
      serviceConfig.LoadCredential = mkIf (cfg.passwordSecretName != null) [
        "pve_password:${config.sops.secrets."${cfg.passwordSecretName}".path}"
      ];

      script = ''
        # Packaged NXD places provider binaries under libexec/nxd beside the nxd wrapper.
        exec ${pkgs.nxd}/bin/nxd bootstrap serve ${planFile}
      '';

      serviceConfig = {
        # Bounded serve exits 0 after timeoutSeconds. Keep the disposable
        # router-recovery PXE path available across that exit; portable one-shot
        # operators still stop the unit explicitly when finished.
        Restart = "always";
        RestartSec = 5;
        RuntimeDirectory = "nxd-pve-bootstrap";
        RuntimeDirectoryMode = "0700";
      };
    };

    # Firewall configuration
    networking.firewall = {
      allowedTCPPorts = [ 80 ]; # HTTP asset serving
      allowedUDPPorts = [ 69 ] ++ (if cfg.dhcpBackend == "dnsmasq" then [ 67 ] else [ ]);
    };
  };
}
