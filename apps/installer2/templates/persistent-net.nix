{ config, pkgs, ... }:
{
  # Enforce ethX naming to match installer environment assumptions
  boot.kernelParams = [ "net.ifnames=0" "biosdevname=0" ];

  networking = {
    useDHCP = false;
    defaultGateway = "{{GATEWAY}}";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    interfaces.{{INTERFACE}}.ipv4.addresses = [{
      address = "{{IP}}";
      prefixLength = {{CIDR}};
    }];
    {{VLAN_CONFIG}}
  };
}
