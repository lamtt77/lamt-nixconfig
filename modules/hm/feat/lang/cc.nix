{
  config,
  pkgs,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    clang
    # gcc
    bear
    cmake
    llvmPackages.libcxx
  ];
}
