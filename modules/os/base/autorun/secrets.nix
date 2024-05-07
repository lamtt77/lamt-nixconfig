{ config, lib, hostname, ... }: let
  cfgAge = config.modules.os.base.services.agenix;
in
with lib;
{
  config = mkIf cfgAge.enable {
    age.secrets."${hostname}/id_agenix".mode = "0600";

    environment.etc = {
      "ssh/id_agenix".source = config.age.secrets."${hostname}/id_agenix".path;
    };
  };
}
