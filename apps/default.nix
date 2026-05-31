{
  inputs,
  pkgs,
  mydefs,
  ...
}: {
  readme = import ./readme.nix {inherit inputs pkgs;};
  format-disko = import ./format-disko.nix {inherit inputs pkgs;};
  installer = import ./installer.nix {inherit inputs pkgs;};
  installer-rs = import ./installer-rs.nix {inherit inputs pkgs;};
}