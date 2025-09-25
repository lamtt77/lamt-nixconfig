{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.hm.base.lang.cc;
in {
  options.modules.hm.base.lang.cc = with types; {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      clang
      # gcc
      bear
      cmake
      llvmPackages.libcxx
    ];
  };
}
