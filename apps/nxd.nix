{ pkgs, inputs, ... }:
let
  nxdPkg = pkgs.callPackage ../pkgs/nxd { inherit inputs; };
in
{
  type = "app";
  program = "${nxdPkg}/bin/nxd";
}
