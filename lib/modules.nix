{ self, lib, ... }:

let
  inherit (builtins) attrValues readDir pathExists concatLists;
  inherit (lib) id mapAttrsToList filterAttrs hasPrefix hasSuffix nameValuePair removeSuffix;
  inherit (self.attrs) mapFilterAttrs;
in
rec {
  # return attrs (dirs and exclude '_') SET - as { name=value; ... }
  # only process 'default.nix' in the sub-dir
  # LamT fixed: if hasPrefix "_", then do not run function 'fn' too!
  mapModules = dir: fn:
    mapFilterAttrs
      (n: v:
        v != null &&
        !(hasPrefix "_" n))
      (n: v:
        let path = "${toString dir}/${n}"; in
        if v == "directory" && pathExists "${path}/default.nix" && !(hasPrefix "_" n)
        then nameValuePair n (fn path)
        else if v == "regular" &&
                n != "default.nix" &&
                hasSuffix ".nix" n  && !(hasPrefix "_" n)
        then nameValuePair (removeSuffix ".nix" n) (fn path)
        else nameValuePair "" null)
      (readDir dir);

  # return attrs (dirs and exclude '_') LIST - as [ value; ... ]
  # only process 'default.nix' in the sub-dir
  mapModules' = dir: fn:
    attrValues (mapModules dir fn);

  # mapModules recursive, map to attrset, ignore 'default.nix'
  # LamT fixed: if hasPrefix "_", then do not run function 'fn' too!
  mapModulesRec = dir: fn:
    mapFilterAttrs
      (n: v:
        v != null &&
        !(hasPrefix "_" n))
      (n: v:
        let path = "${toString dir}/${n}"; in
        if v == "directory" && !(hasPrefix "_" n)
        then nameValuePair n (mapModulesRec path fn)
        else if v == "regular" && n != "default.nix" && hasSuffix ".nix" n && !(hasPrefix "_" n)
        then nameValuePair (removeSuffix ".nix" n) (fn path)
        else nameValuePair "" null)
      (readDir dir);

  # mapModules' recursive, map to list, include 'default.nix' but except its top-level
  mapModulesRec' = dir: fn:
    let
      dirs =
        mapAttrsToList
          (k: _: "${dir}/${k}")
          (filterAttrs
            (n: v: v == "directory" && !(hasPrefix "_" n))
            (readDir dir));
      files = attrValues (mapModules dir id);
      paths = files ++ concatLists (map (d: mapModulesRec' d id) dirs);
    in map fn paths;
}
