{
  inputs,
  pkgs,
  mydefs,
  ...
}:
let
  nxdApp = import ./nxd.nix { inherit inputs pkgs; };
in
{
  readme = import ./readme.nix { inherit inputs pkgs; };
  nxd = nxdApp;
  installer-rs = nxdApp;
}
