{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-medo.nix
    (import ../../modules/disko {
      inherit inputs;
      variant = "digitalocean";
    })
  ];

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
      grub = {
        enable = true;
        device = "nodev";
      };
    };

    growPartition = true;

    # Enable IP forwarding for NAT.
    kernel.sysctl."net.ipv4.ip_forward" = 1;
  };
  networking = {
    hostName = "medo";
    useDHCP = false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];

    # --- WireGuard Server ---
    # This replaces the generic `modules.os.base.services.wireguard.enable = true;`
    # and declaratively sets up the interface and peers.
    wireguard.interfaces.wg0do = {
      ips = [ "10.9.0.1/24" ];
      listenPort = 57921;

      privateKeyFile = config.sops.secrets.wg0do_private_key.path;

      peers = [
        {
          publicKey = "/Vsxe0gjSrwW0rSQaqoQk0UEXOnRe/cEBWXuMJLG7Ws=";
          allowedIPs = [ "10.9.0.2/32" ];
        }
        {
          publicKey = "0ILrE4OxliW69TOVZGyQFxcswt8CG+2cBc+76iQt0CA=";
          allowedIPs = [ "10.9.0.3/32" ];
        }
        {
          publicKey = "082NF0z+hyso3urs13+OTGdIf7v5SGjZ42mbP7JHEk8=";
          allowedIPs = [ "10.9.0.4/32" ];
        }
      ];
    };

    # --- Firewall & NAT ---
    # This declaratively handles the firewall and NAT rules from PostUp/PostDown scripts.
    firewall = {
      allowedTCPPorts = [
        22
        80
        443
      ]; # SSH and Caddy
      allowedUDPPorts = [
        443
        57921
      ]; # Caddy (HTTP/3 QUIC) and WireGuard

      # Allow DNS requests from WireGuard clients to dnsmasq
      interfaces.wg0do = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };
    };

    # The NAT module automatically handles forwarding and masquerading.
    nat = {
      enable = true;
      internalInterfaces = [ "wg0do" ];
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
      settings = {
        # This host is deployed on DigitalOcean; the Proxmox disposable test
        # inherits the configuration but has no metadata service. Restricting
        # discovery keeps DigitalOcean cloud-init behavior while letting the
        # test fall back immediately instead of probing EC2 for four minutes.
        datasource_list = [
          "DigitalOcean"
          "None"
        ];

        # SOPS decrypts with the pre-staged host SSH key. Do not let cloud-init
        # delete and regenerate it on first boot.
        ssh_deletekeys = false;
        ssh_genkeytypes = [ ];
      };
    };
    # --- DNS for VPN Clients ---
    dnsmasq = {
      enable = true;
      settings = {
        listen-address = [ "10.9.0.1" ];
        bind-interfaces = true;
        server = [
          "1.1.1.1"
          "8.8.8.8"
        ]; # Forwards queries to Cloudflare/Google DNS
      };
    };
    caddy = {
      enable = true;
      globalConfig = ''
        skip_install_trust
      '';
      # Cache policy: HTML must revalidate, fingerprinted assets may not.
      #
      # A blanket max-age=3600 on HTML meant a deploy stayed invisible for an
      # hour, and a stale page kept referencing the asset URLs it was built
      # with. Hugo fingerprints CSS and JS with a content hash, so those URLs
      # change whenever their content does and are safe to cache immutably;
      # HTML has a stable URL and must be revalidated instead.
      virtualHosts."blog.lamhub.com".extraConfig = ''
        root * ${pkgs.callPackage ../../pkgs/blog { inherit inputs; }}
        header ETag {file.etag}

        @fingerprinted path_regexp \.[0-9a-f]{32,64}\.(css|js)$
        header @fingerprinted Cache-Control "public, max-age=31536000, immutable"

        @static {
          path *.css *.js *.svg *.png *.jpg *.jpeg *.webp *.woff2 *.ico
          not path_regexp \.[0-9a-f]{32,64}\.(css|js)$
        }
        header @static Cache-Control "public, max-age=86400"

        @documents path *.html */ /
        header @documents Cache-Control "public, max-age=0, must-revalidate"

        file_server
        encode gzip
      '';
      virtualHosts."blog.lamhub.me".extraConfig = ''
        tls internal
        root * ${pkgs.callPackage ../../pkgs/blog { inherit inputs; }}
        file_server
      '';
      virtualHosts."lamhub.com".extraConfig = ''
        respond "Site Under Construction"
      '';
      virtualHosts."nxd.lamhub.com".extraConfig = ''
        root * ${inputs.nxd.packages.${pkgs.system}.site}
        header ETag {file.etag}

        @fingerprinted path_regexp \.[0-9a-f]{32,64}\.(css|js)$
        header @fingerprinted Cache-Control "public, max-age=31536000, immutable"

        @static {
          path *.css *.js *.svg *.png *.jpg *.jpeg *.webp *.woff2 *.ico
          not path_regexp \.[0-9a-f]{32,64}\.(css|js)$
        }
        header @static Cache-Control "public, max-age=86400"

        @documents path *.html */ /
        header @documents Cache-Control "public, max-age=0, must-revalidate"

        file_server
        encode gzip
      '';
    };
    prometheus.exporters.node = {
      enable = true;
    };
  };

  systemd.services."cloud-config".serviceConfig.SuccessExitStatus = "1";
  systemd.services."cloud-final".serviceConfig.SuccessExitStatus = "2";

  environment.systemPackages = with pkgs; [
    # corosync-qdevice
    hugo
    git
  ];

  # systemd.packages = [ pkgs.corosync-qdevice ];
  # systemd.services.corosync-qnetd.wantedBy = [ "multi-user.target" ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
