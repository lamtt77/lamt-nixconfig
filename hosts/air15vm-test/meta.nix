let
  mydefs = import ../../defines.nix;
in
{
  disposable = true;
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
    ../../modules/os/feat/linux/desktop/bspwm-minimal.nix
  ];

  deployment = {
    bootstrapUser = "root";
    diskSize = "64";
    lowMem = "yes";
    localEval = true;
    nameservers = mydefs.networkingDefaults.nameservers;
    vmware = {
      vmxPath = "/Users/lamt/Virtual Machines.localized/air15vm-test.vmwarevm/air15vm-test.vmx";
      cores = 4;
      memoryMiB = 4096;
    };
  };
}
