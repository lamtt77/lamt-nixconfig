# nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=./hosts/minimal-iso/default.nix

{ modulesPath, pkgs, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  environment.systemPackages = with pkgs; [
    nixFlakes
    zsh
    git
    # vim # default included
  ];
}
