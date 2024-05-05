{ inputs, pkgs, ... }: {
  readme = import ./readme.nix { inherit inputs pkgs; };
  format-disko = import ./format-disko.nix { inherit inputs pkgs; };
  installer = import ./installer.nix { inherit inputs pkgs; };
  installer-staging = import ./installer-staging { inherit inputs pkgs; };
  installer-nixos-enter = import ./installer-nixos-enter.nix { inherit inputs pkgs; };
}
