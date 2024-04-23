# NOTE: out-of-dated, not using
# reference:  https://www.funtoo.org/Funtoo:Keychain

{ inputs, config, lib, ... }:

with lib;
let
  inherit (inputs.self) mydefs;
  cfg = config.modules.hm.linux.keychain;
in {
  options.modules.hm.linux.keychain = with types; {
    enable = mkEnableOption "Keychain Helper";
  };

  config = mkIf cfg.enable {
    programs.keychain = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
      # extraFlags = ["--ignore-missing" "--quiet"];
      # keys = ["id_ed25519" "id_rsa"];
      agents = ["gpg"];
      keys = ["${mydefs.gpg-sshKey}"];
    };
  };
}
