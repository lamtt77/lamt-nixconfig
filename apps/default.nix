{ pkgs, ... }: {
  readme = import ./readme.nix { inherit pkgs; };
}
