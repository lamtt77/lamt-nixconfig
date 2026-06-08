{ pkgs, ... }:
let
  installerPkg = pkgs.callPackage ../pkgs/installer-rs { };
in
{
  type = "app";
  program = "${installerPkg}/bin/lamd";
}
