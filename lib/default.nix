{
  inputs,
  lib,
  mydefs,
  ...
}:
let
  # Statically import library components (zero filesystem IO, LSP-friendly)
  loader = import ./loader.nix { inherit lib; };
  my = import ./my.nix { inherit lib mydefs; };
  systems = import ./systems.nix { inherit inputs lib; };
in
# Flatten the library namespace directly (fully compatible with existing usage)
loader // my // systems
