# Shell for bootstrapping flake-enabled nix and home-manager
{
  pkgs ? let
    # If pkgs is not defined, instantiate nixpkgs from locked commit
    lock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
    nixpkgs = fetchTarball {
      url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
      sha256 = lock.narHash;
    };
    system = builtins.currentSystem;
    overlays = []; # Explicit blank overlay to avoid interference
  in
    import nixpkgs {inherit system overlays;},
  inputs ? null,
  ...
}:
pkgs.mkShell {
  # Enable experimental features without having to specify the argument
  NIX_CONFIG = "extra-experimental-features = nix-command flakes";
  nativeBuildInputs = with pkgs; [nix home-manager git hugo];

  shellHook = ''
    # Link Hugo theme if we are in the project root and inputs are available
    if [ -d "blog" ] && [ -n "${inputs.hugo-papermod or ""}" ]; then
      mkdir -p blog/themes
      if [ ! -L "blog/themes/hugo-papermod" ]; then
        echo "Linking Hugo theme from Nix store..."
        rm -rf blog/themes/hugo-papermod
        ln -s ${inputs.hugo-papermod} blog/themes/hugo-papermod
      fi
    fi
  '';
}
