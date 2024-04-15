{ config, pkgs, lib, ... }:

with lib;
let cfg = config.modules.hm.base.pass;
in {
  options.modules.hm.base.pass = with types; {
    enable = mkEnableOption "Password Store Utility";
    passwordStoreDir = mkOption {type = str; default = "$HOME/.secrets/password-store";};
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      (pass.withExtensions (exts: [
        exts.pass-otp
        # exts.pass-genphrase
        # exts.pass-tomb # does not build on darwin
      ]))
    ];
    home.sessionVariables.PASSWORD_STORE_DIR = cfg.passwordStoreDir;
  };
}
