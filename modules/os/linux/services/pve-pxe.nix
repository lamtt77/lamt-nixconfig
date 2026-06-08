{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.os.linux.services.pve-pxe;
in
{
  options.modules.os.linux.services.pve-pxe = {
    enable = mkEnableOption "Proxmox VE PXE bootstrap service";

    assets = mkOption {
      type = types.package;
      description = "Target-specific pure PXE assets package built by mkPvePxeAssets.";
    };

    interface = mkOption {
      type = types.str;
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
        - "none": Another DHCP daemon (e.g. Kea) owns IP leasing and PXE options; TFTP runs via atftpd.
        - "dnsmasq": dnsmasq runs on the interface, providing isolated DHCP/TFTP.
      '';
    };

    passwordSecretName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOPS secret name containing the temporary installer root password.";
    };

    vrrpControlled = mkOption {
      type = types.bool;
      default = false;
      description = "Whether service lifecycle is managed by VRRP state transitions.";
    };
  };

  config = mkIf cfg.enable {
    # Clear wantedBy for atftpd if managed by keepalived (overriding upstream NixOS service)
    systemd.services.atftpd.wantedBy = mkForce (
      if cfg.vrrpControlled then [ ] else [ "multi-user.target" ]
    );

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
    ];

    # SOPS secret reference for systemd credential binding
    sops.secrets = mkIf (cfg.passwordSecretName != null) {
      "${cfg.passwordSecretName}" = { };
    };

    # 1. Python Answer/Asset HTTP Server
    systemd.services.pve-answer-server = {
      description = "Proxmox VE Auto-Install Answer and HTTP Asset Server";
      wantedBy = if cfg.vrrpControlled then [ ] else [ "multi-user.target" ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      # Load SOPS secret into systemd credential
      serviceConfig.LoadCredential = mkIf (cfg.passwordSecretName != null) [
        "pve_password:${config.sops.secrets."${cfg.passwordSecretName}".path}"
      ];

      # Pre-start script to materialize answer file with the secret password under /run
      preStart = ''
        mkdir -p /run/pve-pxe
        chmod 700 /run/pve-pxe

        if [ -f "$CREDENTIALS_DIRECTORY/pve_password" ]; then
          PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/pve_password")
        else
          echo "Warning: PVE installer password credential not found. Using default."
          PASSWORD="changeme"
        fi

        # Materialize TOML with root password
        sed "s/@ROOT_PASSWORD@/$PASSWORD/g" \
          ${cfg.assets}/pve-answer-nonsecret.toml > /run/pve-pxe/pve-answer.toml
        chmod 600 /run/pve-pxe/pve-answer.toml
      '';

      script = ''
        exec ${pkgs.pve-answer-server}/bin/pve-answer-server \
          --host ${cfg.listenAddress} \
          --port 80 \
          --static-dir ${cfg.assets} \
          --answer-file /run/pve-pxe/pve-answer.toml
      '';

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        RuntimeDirectory = "pve-pxe";
        RuntimeDirectoryMode = "0700";
      };
    };

    # 2. TFTP Service & Assets Population (only when external DHCP/Kea owns L2 segment)
    services.atftpd = mkIf (cfg.dhcpBackend == "none") {
      enable = true;
      root = "/var/lib/tftpboot";
    };

    systemd.services.populate-pve-pxe-tftp = mkIf (cfg.dhcpBackend == "none") {
      description = "Populate TFTP directory with PXE bootloaders";
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /var/lib/tftpboot/ipxe
        ln -sf ${cfg.assets}/ipxe/undionly.kpxe /var/lib/tftpboot/ipxe/undionly.kpxe
        ln -sf ${cfg.assets}/ipxe/ipxe.efi /var/lib/tftpboot/ipxe/ipxe.efi
        ln -sf ${cfg.assets}/autoexec.ipxe /var/lib/tftpboot/autoexec.ipxe
      '';
      serviceConfig.Type = "oneshot";
    };

    # 3. dnsmasq isolated DHCP/TFTP server (only when dnsmasq backend is selected)
    services.dnsmasq = mkIf (cfg.dhcpBackend == "dnsmasq") {
      enable = true;
      settings = {
        interface = cfg.interface;
        bind-interfaces = true;
        port = 0; # Disable DNS resolver
        dhcp-range = "192.168.250.100,192.168.250.150,12h";
        dhcp-option = [
          "option:router,${cfg.listenAddress}"
          "option:dns-server,${cfg.listenAddress}"
        ];
        enable-tftp = true;
        # dnsmasq serves TFTP files directly from the Nix store!
        tftp-root = "${cfg.assets}";
        dhcp-boot = [
          "tag:ipxe,autoexec.ipxe"
          "tag:!ipxe,tag:efi,ipxe/ipxe.efi"
          "tag:!ipxe,tag:pxe,ipxe/undionly.kpxe"
        ];
        # Architecture tag-matching (EFI vs Legacy BIOS)
        dhcp-match = [
          "set:ipxe,175"
          "set:efi,option:client-arch,7"
          "set:efi,option:client-arch,9"
          "set:efi,option:client-arch,11"
          "set:pxe,option:client-arch,0"
        ];
      };
    };

    # Firewall configuration
    networking.firewall = {
      allowedTCPPorts = [ 80 ]; # HTTP asset serving
      allowedUDPPorts = mkIf (cfg.dhcpBackend == "none") [ 69 ]; # TFTP port (when using atftpd)
    };
  };
}
