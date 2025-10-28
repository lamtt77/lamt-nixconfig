{
  inputs,
  pkgs,
  mydefs,
  ...
}: {
  readme = import ./readme.nix {inherit inputs pkgs;};
  format-disko = import ./format-disko.nix {inherit inputs pkgs;};
  installer-staging = import ./installer-staging/orchestrator.nix {inherit inputs pkgs mydefs;};
}
