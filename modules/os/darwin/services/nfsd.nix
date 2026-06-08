# start/stop/status service: sudo nfsd start/stop/status
# test: showmount -e
{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.os.darwin.services.nfsd;
in
{
  options = with types; {
    modules.os.darwin.services.nfsd = {
      enable = mkEnableOption "NFS Daemon";
    };
  };
  config = mkIf cfg.enable {
    sops.secrets = {
      "nfsd-exports" = { };
    };

    environment.etc = {
      "exports".source = config.sops.secrets."nfsd-exports".path;
    };
  };
}
