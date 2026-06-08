{
  class = "nixos";
  system = "aarch64-linux";
  username = "lamt";
  server = false;
  wsl = false;
  home = false;
  hasDisko = true;

  deployment = {
    targetIp = "";
    diskSize = "64";
    lowMem = "yes";
    vmware = {
      vmxPath = "/Users/lamt/Virtual Machines.localized/air15vm-nixos-25.11.vmwarevm/air15vm-nixos-25.11.vmx";
    };
  };
}
