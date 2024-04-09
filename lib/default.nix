{ inputs, lib, pkgsall, ... }:

let
  inherit (lib) makeExtensible attrValues foldr;
  inherit (modules) mapModules;

  modules = import ./modules.nix {
    inherit lib;
    self.attrs = import ./attrs.nix { inherit lib; };
  };

  mylib = makeExtensible (self:
    mapModules ./. (file: import file { inherit self inputs lib pkgsall; })
  );
in
mylib.extend
  (final: prev:
    foldr (a: b: a // b) {} (attrValues prev))
