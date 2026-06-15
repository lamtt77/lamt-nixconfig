# start/stop/status service: sudo nfsd start/stop/status
# test: showmount -e
{
  config,
  ...
}:
{
  sops.secrets = {
    "nfsd-exports" = { };
  };

  environment.etc = {
    "exports".source = config.sops.secrets."nfsd-exports".path;
  };
}
