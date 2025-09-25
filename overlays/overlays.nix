{inputs}: {
  default = final: prev: rec {
    # provide 'pkgs.unstable'
    unstable = import inputs.nixpkgs-unstable {
      inherit (prev) system;
      config.allowUnfree = true;
      config.allowUnsupportedSystem = true;
    };

    firefox-addons = inputs.firefox-addons.packages.${prev.system};

    # bleeding stuffs
    inherit (unstable) helix;

    ovftool = prev.ovftool.override {acceptBroadcomEula = true;};
  };

  disko = final: prev: {
    inherit (inputs.disko.packages.${prev.system}) disko;
  };

  sops-nix = inputs.sops-nix.overlays.default;

  # packages at pkgs/_manual are for manually load on-demand
  packages = final: prev: {
    create-dmg = final.callPackage ../pkgs/_manual/create-dmg.nix {};

    # Fix 1password not working properly on Linux arm64.
    _1password = final.callPackage ../pkgs/_manual/1password.nix {};
  };
}
