{
  config,
  lib,
  mydefs,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.os.linux.services.router;
in
{
  options.modules.os.linux.services.router = {
    enable = mkEnableOption "NixOS router/firewall service";

    isMaster = mkOption {
      type = types.bool;
      description = "Whether this is the master router in HA setup";
    };

    wanIp = mkOption {
      type = types.str;
      description = "WAN interface IP for this router";
    };

    lanIp = mkOption {
      type = types.str;
      description = "LAN interface IP for this router";
    };

    syncIp = mkOption {
      type = types.str;
      description = "Sync VLAN IP for HA";
    };

    vipLan = mkOption {
      type = types.str;
      description = "LAN virtual IP";
    };

    vipWan = mkOption {
      type = types.str;
      description = "WAN virtual IP";
    };

    hostname = mkOption {
      type = types.str;
      description = "System hostname";
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      default = [
        "1.1.1.1"
        "8.8.8.8"
      ];
      description = "DNS servers";
    };

    extraInternalInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional internal interfaces included in router NAT.";
    };

    enableHA = mkOption {
      type = types.bool;
      default = true;
      description = "Enable HA with Keepalived";
    };

    enableDhcp = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the production LAN Kea DHCP service";
    };

    priority = mkOption {
      type = types.int;
      description = "VRRP priority for Keepalived";
    };

    enablePxe = mkOption {
      type = types.bool;
      default = false;
      description = "Enable PXE boot service";
    };

    pxeTarget = mkOption {
      type = types.enum [
        "pve1"
        "pve2"
        "pve-test"
      ];
      default = "pve2";
      description = "The target profile to boot via PXE (pve1, pve2, or pve-test)";
    };

    enableDyndns = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Cloudflare Dynamic DNS updates";
    };
  };

  config = mkIf cfg.enable {
    modules.os.linux.services.router.priority = mkDefault (if cfg.isMaster then 150 else 100);

    networking = {
      hostName = cfg.hostname;
      nameservers = cfg.dnsServers;

      vlans = {
        "eth1.10" = {
          id = 10;
          interface = "eth1";
        };
        "eth1.40" = {
          id = 40;
          interface = "eth1";
        };
      };

      interfaces = {
        "eth0".useDHCP = false;
        "eth1.10".useDHCP = false;
        "eth1.40".useDHCP = false;
      };

      interfaces."eth0".ipv4.addresses = [
        {
          address = cfg.wanIp;
          prefixLength = 24;
        }
      ];
      interfaces."eth1.10".ipv4.addresses = [
        {
          address = cfg.lanIp;
          prefixLength = 24;
        }
      ];
      interfaces."eth1.40".ipv4.addresses = [
        {
          address = cfg.syncIp;
          prefixLength = 24;
        }
      ];

      defaultGateway = {
        address = "192.168.0.1";
        interface = "eth0";
      };

      nat = {
        enable = true;
        externalInterface = "eth0";
        internalInterfaces = [ "eth1.10" ] ++ cfg.extraInternalInterfaces;
        forwardPorts = [
          {
            sourcePort = 443;
            proto = "tcp";
            destination = "192.168.1.18:443";
          }
        ];
      };

      firewall = {
        enable = true;
        allowedTCPPorts = [
          22
          80
          443
        ]
        ++ (lib.optionals cfg.enableHA [ 8000 ]);
        allowedUDPPorts = [
          53
          3478
        ];
        extraCommands = ''
          iptables -A INPUT -p vrrp -j ACCEPT
          iptables -A OUTPUT -p vrrp -j ACCEPT
        '';
      };
    };

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    services.unbound = {
      enable = true;
      settings.server = {
        interface = [
          "127.0.0.1"
          cfg.lanIp
        ]
        ++ (if cfg.enableHA then [ cfg.vipLan ] else [ ]);
        access-control = [
          "192.168.1.0/24 allow"
        ];
        do-ip6 = "no";
        verbosity = 1;
        local-data = [
          "\"minecraft.lamhub.com A 192.168.1.168\""
          "\"nas.lamhub.lan A ${mydefs.nasIp}\""
          "\"pve1.lamhub.com A ${mydefs.hosts.pve1.ip}\""
          "\"pve2.lamhub.com A ${mydefs.hosts.pve2.ip}\""
          "\"smtp.lamhub.lan A 192.168.1.18\""
          "\"tea.lamhub.com A 192.168.1.18\""
          "\"ts.lamhub.com A 192.168.1.18\""
        ];
      };
    };

    services.kea = mkIf cfg.enableDhcp {
      dhcp4 = {
        enable = true;
        settings = lib.mkMerge [
          {
            interfaces-config = {
              interfaces = [ "eth1.10" ];
            };
            "control-socket" = {
              "socket-type" = "unix";
              "socket-name" = "/run/kea/kea4-ctrl-socket";
            };
            "lease-database" = {
              "type" = "memfile";
              "persist" = true;
              "name" = "/var/lib/kea/kea-leases4.csv";
              "lfc-interval" = 3600;
            };
            "multi-threading" = {
              "enable-multi-threading" = true;
              "thread-pool-size" = 4;
              "packet-queue-size" = 64;
            };
            "valid-lifetime" = 3600;
            "renew-timer" = 1800;
            "rebind-timer" = 3000;
            "cache-threshold" = 0.25;
            loggers = [
              {
                name = "kea-dhcp4";
                output_options = [
                  {
                    output = "stdout";
                  }
                ];
                severity = "INFO";
                debuglevel = 99;
              }
            ];
            # Define the Custom Proxmox Options (Global) ---
            # "option-def" = [
            #   {
            #     name = "proxmox-auto-install-url";
            #     code = 250;
            #     type = "string";
            #     space = "dhcp4";
            #   }
            #   {
            #     name = "proxmox-auto-install-cert-fingerprint";
            #     code = 251;
            #     type = "string";
            #     space = "dhcp4";
            #   }
            # ];
            subnet4 = [
              {
                id = 1;
                subnet = "192.168.1.0/24";
                option-data = [
                  {
                    name = "routers";
                    data = cfg.vipLan;
                  }
                  {
                    name = "domain-name-servers";
                    data = cfg.vipLan;
                  }
                  # --- Proxmox Auto-Install Options ---
                  # {
                  #   name = "proxmox-auto-install-url";
                  #   data = "http://${cfg.vipLan}/pve2-answer.toml";
                  # }
                  # Optional: Uncomment this if you use HTTPS with a self-signed cert
                  # {
                  #   name = "proxmox-auto-install-cert-fingerprint";
                  #   data = "AB:CD:EF:12:34:56:...."; # <-- Your SHA256 fingerprint
                  # }
                ];
                pools = [ { pool = "192.168.1.100 - 192.168.1.199"; } ];
                reservations = [
                  {
                    hw-address = "c8:b8:2f:5d:4b:8d";
                    ip-address = "192.168.1.4";
                    hostname = "eero";
                  }
                ];
                "next-server" = cfg.vipLan;
              }
            ];
            client-classes = [
              {
                name = "iPXE";
                test = "option[175].exists";
                "boot-file-name" = "autoexec.ipxe";
              }
              {
                name = "UEFI";
                test = "option[93].hex == 0x0007 or option[93].hex == 0x0009";
                "boot-file-name" = "ipxe/ipxe.efi";
              }
              {
                name = "BIOS";
                test = "not (option[93].hex == 0x0007 or option[93].hex == 0x0009)";
                "boot-file-name" = "ipxe/undionly.kpxe";
              }
            ];
          }
          (mkIf cfg.enableHA {
            "hooks-libraries" = [
              {
                library = "${pkgs.kea}/lib/kea/hooks/libdhcp_lease_cmds.so";
              }
              {
                library = "${pkgs.kea}/lib/kea/hooks/libdhcp_ha.so";
                parameters."high-availability" = [
                  {
                    "this-server-name" = if cfg.isMaster then "router-main" else "router-backup";
                    "mode" = "hot-standby";
                    "http-host" = cfg.lanIp;
                    "http-port" = 8000;
                    "max-unacked-clients" = 0;
                    "heartbeat-delay" = 2000;
                    "max-response-delay" = 10000;
                    "max-ack-delay" = 5000;
                    "sync-timeout" = 60000;
                    "sync-leases" = true;
                    "peers" = [
                      {
                        "name" = "router-main";
                        "url" = "http://192.168.1.2:8000/";
                        "role" = "primary";
                        "auto-failover" = true;
                      }
                      {
                        "name" = "router-backup";
                        "url" = "http://192.168.1.3:8000/";
                        "role" = "standby";
                        "auto-failover" = true;
                      }
                    ];
                  }
                ];
              }
            ];
          })
        ];
      };
    };

    modules.os.linux.services.pve-pxe = mkIf cfg.enablePxe {
      enable = true;
      assets = pkgs.pve-pxe-assets.mkPvePxeAssets {
        target = cfg.pxeTarget;
        bootstrapIp = cfg.vipLan;
      };
      interface = "eth1.10";
      listenAddress = cfg.vipLan;
      dhcpBackend = "none";
      vrrpControlled = cfg.enableHA;
    };

    sops.secrets.cloudflare_dns_api_token = mkIf cfg.enableDyndns { };

    services.cloudflare-dyndns = mkIf cfg.enableDyndns {
      enable = true;
      apiTokenFile = config.sops.secrets.cloudflare_dns_api_token.path;
      domains = [ "lam.lamhub.com" ];
    };

    services.keepalived = mkIf cfg.enableHA {
      enable = true;
      vrrpInstances.lan = {
        interface = "eth1.40";
        virtualRouterId = 52;
        state = if cfg.isMaster then "MASTER" else "BACKUP";
        inherit (cfg) priority;
        virtualIps = [
          {
            addr = "${cfg.vipLan}";
            dev = "eth1.10";
          }
          {
            addr = "${cfg.vipWan}";
            dev = "eth0";
          }
        ];
        trackInterfaces = [
          "eth0"
          "eth1.10"
          "eth1.40"
        ];
        unicastPeers = [
          (if cfg.isMaster then "192.168.4.3" else "192.168.4.2")
        ];
        extraConfig = ''
          garp_master_delay 5
          garp_master_repeat 3
          garp_master_refresh 10
          notify ${pkgs.writeShellScript "keepalived-lan-notify" ''
            TYPE=$1
            NAME=$2
            STATE=$3

            case "$STATE" in
              "MASTER")
                ${
                  if cfg.enablePxe then
                    ''
                      systemctl start pve-answer-server.service atftpd.service
                    ''
                  else
                    "echo 'PXE not enabled on MASTER state'"
                }
                ;;
              "BACKUP"|"FAULT")
                ${
                  if cfg.enablePxe then
                    ''
                      systemctl stop pve-answer-server.service atftpd.service
                    ''
                  else
                    "echo 'PXE not enabled on BACKUP/FAULT state'"
                }
                ;;
            esac
          ''}
        '';
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/kea 0755 kea kea -"
      "d /var/log/kea 0755 kea kea -"
      "d /run/kea 0755 kea kea -"
    ];
  };
}
