{
  class = "darwin";
  system = "aarch64-darwin";
  username = "lamt";
  home = true;

  role = "workstation";

  osFeatures = [
    ../../modules/os/feat/services/wireguard.nix
    ../../modules/os/feat/services/builders.nix
    ../../modules/os/feat/darwin/services/nfsd.nix
  ];

  hmFeatures = [
    ../../modules/hm/feat/editors/doomemacs.nix
  ];
}
