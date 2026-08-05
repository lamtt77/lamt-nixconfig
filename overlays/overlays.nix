{ inputs }:
let
  otherOverlays = {
    disko = final: prev: {
      inherit (inputs.disko.packages.${prev.stdenv.hostPlatform.system}) disko;
    };

    sops-nix = inputs.sops-nix.overlays.default;

    # packages at pkgs/_manual are for manually load on-demand
    packages = final: prev: {
      create-dmg = final.callPackage ../pkgs/_manual/create-dmg.nix { };
      codelldb = final.callPackage ../pkgs/_manual/codelldb.nix { };
    };

    self-packages =
      final: prev:
      let
        mydefs = import ../defines.nix;
      in
      {
        nxd = inputs.nxd.packages.${final.stdenv.hostPlatform.system}.nxd;
        pve-pxe-assets = final.callPackage ../pkgs/pve-pxe-assets { inherit inputs mydefs; };
        # st with scrollback (100k), scrollback-mouse, scrollback-mouse-altscreen, clipboard patches
        st-custom = final.callPackage ../pkgs/st { };
      };

    # Targeted unstable package mapping to prevent importing the entire nixpkgs-unstable channel multiple times
    unstable-packages =
      final: prev:
      let
        unstable-pkgs = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system};
      in
      {
        neovim = unstable-pkgs.neovim;
        ghostty = unstable-pkgs.ghostty;
        unstable-nix = unstable-pkgs.nixVersions.latest;
        hyprland = unstable-pkgs.hyprland;
        xdg-desktop-portal-hyprland = unstable-pkgs.xdg-desktop-portal-hyprland;
        cloudflared = unstable-pkgs.cloudflared;
        ripdrag = unstable-pkgs.ripdrag;
        wev = unstable-pkgs.wev;
        wl-clipboard = unstable-pkgs.wl-clipboard;
        wtype = unstable-pkgs.wtype;
        swappy = unstable-pkgs.swappy;
        slurp = unstable-pkgs.slurp;
        swayimg = unstable-pkgs.swayimg;
        imv = unstable-pkgs.imv;
        opencode = unstable-pkgs.opencode;
        gemini-cli = unstable-pkgs.gemini-cli;
      };
  };
in
otherOverlays
