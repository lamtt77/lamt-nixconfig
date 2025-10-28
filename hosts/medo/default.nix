{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  blog = pkgs.stdenv.mkDerivation {
    name = "blog";
    src = ../../blog;
    buildInputs = [pkgs.hugo];
    buildPhase = "hugo --minify";
    installPhase = "cp -r public $out";
  };
in {
  imports = [
    ./hardware-medo.nix
    (import ../_disko/digitalocean.nix {
      inherit inputs;
    })
  ];

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
      grub = {
        enable = true;
        device = "";
      };
    };

    growPartition = true;

    # Enable IP forwarding for NAT.
    kernel.sysctl."net.ipv4.ip_forward" = 1;
  };
  networking = {
    hostName = "medo";
    useDHCP = false;
    nameservers = ["1.1.1.1" "8.8.8.8"];

    # --- WireGuard Server ---
    # This replaces the generic `modules.os.base.services.wireguard.enable = true;`
    # and declaratively sets up the interface and peers.
    wireguard.interfaces.wg0do = {
      ips = ["10.9.0.1/24"];
      listenPort = 57921;

      privateKeyFile = config.sops.secrets.wg0do_private_key.path;

      peers = [
        {
          publicKey = "/Vsxe0gjSrwW0rSQaqoQk0UEXOnRe/cEBWXuMJLG7Ws=";
          allowedIPs = ["10.9.0.2/32"];
        }
        {
          publicKey = "0ILrE4OxliW69TOVZGyQFxcswt8CG+2cBc+76iQt0CA=";
          allowedIPs = ["10.9.0.3/32"];
        }
        {
          publicKey = "082NF0z+hyso3urs13+OTGdIf7v5SGjZ42mbP7JHEk8=";
          allowedIPs = ["10.9.0.4/32"];
        }
      ];
    };

    # --- Firewall & NAT ---
    # This declaratively handles the firewall and NAT rules from PostUp/PostDown scripts.
    firewall = {
      allowedTCPPorts = [22 80 443]; # SSH and Caddy
      allowedUDPPorts = [57921]; # WireGuard

      # Allow DNS requests from WireGuard clients to dnsmasq
      interfaces.wg0do = {
        allowedTCPPorts = [53];
        allowedUDPPorts = [53];
      };
    };

    # The NAT module automatically handles forwarding and masquerading.
    nat = {
      enable = true;
      internalInterfaces = ["wg0do"];
    };
  };

  modules = {
    os = {
      base = {
        services = {
          sops.enable = true;
        };
      };
      base = {
        services = {
          tailscale.enable = true;
        };
      };
      linux = {
        services = {
          openssh.enable = true;
          fail2ban.enable = true;
        };
      };
    };
  };
  sops.secrets.wg0do_private_key = {
    # The key file will be owned by root and readable by the 'systemd-network' group.
    owner = config.users.users.root.name;
    group = config.users.groups.systemd-network.name;
    mode = "0640";
  };
  services = {
    cloud-init = {
      enable = true;
      network.enable = true;
    };
    # --- DNS for VPN Clients ---
    dnsmasq = {
      enable = true;
      settings = {
        listen-address = ["10.9.0.1"];
        bind-interfaces = true;
        server = ["1.1.1.1" "8.8.8.8"]; # Forwards queries to Cloudflare/Google DNS
      };
    };
    caddy = {
      enable = true;
      virtualHosts."blog.lamhub.com".extraConfig = ''
        root * ${blog}
        header Cache-Control max-age=3600
        header ETag {file.etag}
        file_server
        encode gzip
      '';
      virtualHosts."blog.lamhub.me".extraConfig = ''
        tls internal
        root * ${blog}
        file_server
      '';
      virtualHosts."lamhub.com".extraConfig = ''
        respond "Site Under Construction"
      '';
    };
    prometheus.exporters.node = {
      enable = true;
    };
  };

  systemd.services."cloud-config".serviceConfig.SuccessExitStatus = "1";
  systemd.services."cloud-final".serviceConfig.SuccessExitStatus = "2";

  environment.systemPackages = with pkgs; [
    hugo
    git
  ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
