{
  class = "nixos";
  system = "aarch64-linux";
  username = "lamt";
  server = false;
  wsl = false;
  home = false;
  hasDisko = true;

  role = "workstation";
  osFeatures = [
    ../../modules/os/feat/services/builders.nix
    ../../modules/os/feat/linux/services/openssh.nix
    ../../modules/os/feat/linux/desktop/i3.nix
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        authKey = "tailscale_preauth_key";
      };
    }
  ];

  deployment = {
    targetIp = "";
    diskSize = "64";
    lowMem = "yes";
    vmware = {
      vmxPath = "/Users/lamt/Virtual Machines.localized/air15vm-nixos-25.11.vmwarevm/air15vm-nixos-25.11.vmx";
    };
  };
}
