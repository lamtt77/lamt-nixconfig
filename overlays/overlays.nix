{inputs}: {
  default = final: prev: {
    # provide 'pkgs.unstable'
    unstable = import inputs.nixpkgs-unstable {
      inherit (prev) system;
      config.allowUnfree = true;
      config.allowUnsupportedSystem = true;
    };
  };

  disko = final: prev: {
    inherit (inputs.disko.packages.${prev.system}) disko;
  };

  sops-nix = inputs.sops-nix.overlays.default;

  # packages at pkgs/_manual are for manually load on-demand
  packages = final: prev: {
    create-dmg = final.callPackage ../pkgs/_manual/create-dmg.nix {};
    codelldb = final.callPackage ../pkgs/_manual/codelldb.nix {};
  };
}
