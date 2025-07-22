{ config, lib, hostname, ... }: let
  cfgAge = config.modules.os.base.services.agenix;
in
with lib;
{
  config = mkIf cfgAge.enable {
    # age.secrets."${hostname}/id_agenix".mode = "0600";

    # environment.etc = {
    #   "ssh/id_agenix".source = config.age.secrets."${hostname}/id_agenix".path;
    # };

    # system.activationScripts = let
    #   mysecrets = "git+ssh://git@tea.lamhub.com/lamtt77/lamt-secrets";
    # in {
    #   installMysecrets = ''
    #     test -d $HOME/.mysecrets && rm -rf $HOME/.mysecrets
    #     git clone --depth=1 ${mysecrets} $HOME/.mysecret && cd $HOME/.mysecret
    #     git sparse-checkout set agenix/${hostname}
    #     # rm -rf $HOME/.mysecret/.git
    #   '';
    # };
  };
}
