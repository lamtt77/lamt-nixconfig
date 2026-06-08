{ pkgs, lib, ... }:
# Build deterministic gzipped tarball from directory source with ownership and timestamp resets
{
  name,
  src,
  excludeList ? [ ],
}:
pkgs.runCommand "${name}.tar.gz"
  {
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.gzip
    ];
  }
  ''
    tar --owner=0 --group=0 --numeric-owner --sort=name --mtime="@0" \
      ${lib.concatMapStringsSep " " (p: "--exclude='${p}'") excludeList} \
      -czvf $out -C ${src} .
  ''
