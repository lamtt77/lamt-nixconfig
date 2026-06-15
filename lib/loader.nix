{ lib, ... }:
let
  inherit (builtins)
    readDir
    pathExists
    ;
  inherit (lib)
    filterAttrs
    hasPrefix
    hasSuffix
    nameValuePair
    removeSuffix
    mapAttrs'
    ;

  mapFilterAttrs =
    pred: f: attrs:
    filterAttrs pred (mapAttrs' f attrs);
in
{
  # return attrs (dirs and exclude '_') SET - as { name=value; ... }
  # only process 'default.nix' in the sub-dir
  mapPackages =
    dir: fn:
    mapFilterAttrs (n: v: v != null && !(hasPrefix "_" n)) (
      n: v:
      let
        path = "${toString dir}/${n}";
      in
      if v == "directory" && pathExists "${path}/default.nix" && !(hasPrefix "_" n) then
        nameValuePair n (fn path)
      else if v == "regular" && n != "default.nix" && hasSuffix ".nix" n && !(hasPrefix "_" n) then
        nameValuePair (removeSuffix ".nix" n) (fn path)
      else
        nameValuePair "" null
    ) (readDir dir);
}
