{ inputs, config, pkgs, lib, ... }:

with lib;
let cfg = config.modules.hm.base.pass;
    inherit (inputs.self) mydefs;
in {
  options.modules.hm.base.pass = with types; {
    enable = mkEnableOption "Password Store Utility";
    passwordStoreDir = mkOption {type = str; default = "$HOME/.secrets/password-store";};
  };

  config = mkIf cfg.enable {
    # home.sessionVariables.PASSWORD_STORE_DIR = cfg.passwordStoreDir;
    programs.password-store = {
      enable = true;
      package = with pkgs; pass.withExtensions (exts: [
        exts.pass-otp
        # exts.pass-genphrase
        # exts.pass-tomb # does not build on darwin
      ]);
      settings = {
        PASSWORD_STORE_DIR = cfg.passwordStoreDir;
        PASSWORD_STORE_KEY = lib.strings.concatStringsSep " " [
          "${mydefs.gpgEncryption}" # E - LamT
        ];
        PASSWORD_STORE_SIGNING_KEY = lib.strings.concatStringsSep " " [
          "${mydefs.gpgDefaultKey}" # S - LamT
        ];
        PASSWORD_STORE_ENABLE_EXTENSIONS = "true";
      };
    };
  };
}
