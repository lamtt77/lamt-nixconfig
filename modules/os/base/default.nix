{ ... }:
{
  imports = [
    ./core.nix
    ./fonts.nix
    ./nixpath-registry.nix
    ./services/maintenance.nix
    (import ./services/sops { })
    ./update-diff.nix
  ];
}
