# LamT: bleeding edge helix :)

final: prev: {
  helix = prev.helix.overrideAttrs (old: rec {
    pname = "helix";
    version = "24.03";

    src = prev.fetchzip {
      url = "https://github.com/helix-editor/helix/releases/download/${version}/helix-${version}-source.tar.xz";
      hash = "sha256-1myVGFBwdLguZDPo1jrth/q2i5rn5R2+BVKIkCCUalc=";
      stripRoot = false;
    };

    patches = [];

    cargoDeps = old.cargoDeps.overrideAttrs (prev.lib.const {
      name = "${pname}-${version}-vendor.tar.gz";
      inherit src;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-2nkRtJS9OWnwNRtLM/bwC2dlyeCBUs1+UQOTkhj4tBE=";
    });
  });
}
