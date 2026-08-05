{ lib, ... }:
let
  binaryCache = import ./binary-cache.nix { inherit lib; };
in
{
  options = {
    user = lib.mkOption {
      type = lib.types.str;
      description = "Primary user of the system";
    };

    nxd.binaryCache = lib.mkOption {
      type = lib.types.nullOr binaryCache.binaryCacheType;
      default = binaryCache.defaultBinaryCache;
      description = "Optional signed HTTPS binary cache for this host.";
    };
  };
}
