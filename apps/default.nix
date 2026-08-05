{
  inputs,
  pkgs,
  mydefs,
  ...
}:
{
  readme = import ./readme.nix { inherit inputs pkgs; };
}
