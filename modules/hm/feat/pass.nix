{
  passwordStoreDir ? "$HOME/.secrets/password-store",
}:
{
  config,
  pkgs,
  lib,
  mydefs,
  ...
}:
{
  # home.sessionVariables.PASSWORD_STORE_DIR = passwordStoreDir;
  programs.password-store = {
    enable = true;
    package =
      with pkgs;
      pass.withExtensions (exts: [
        exts.pass-otp
      ]);
    settings = {
      PASSWORD_STORE_DIR = passwordStoreDir;
      PASSWORD_STORE_KEY = lib.strings.concatStringsSep " " [
        "${mydefs.gpgEncryption}" # E - LamT
      ];
      PASSWORD_STORE_SIGNING_KEY = lib.strings.concatStringsSep " " [
        "${mydefs.gpgDefaultKey}" # S - LamT
      ];
      PASSWORD_STORE_ENABLE_EXTENSIONS = "true";
    };
  };
}
