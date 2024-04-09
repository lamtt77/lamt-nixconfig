let sources = import ../nix/sources.nix; in
final: prev: {
  buildpack = prev.buildpack.overrideAttrs (oldAttrs: rec {
    version = prev.lib.strings.removePrefix "v" sources.pack.branch;
    src = sources.pack;
    buildFlagsArray = [ "-ldflags=-s -w -X github.com/buildpacks/pack/cmd.Version=${version}" ];
  });
}
