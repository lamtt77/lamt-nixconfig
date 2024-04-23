{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.bash;

  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@lamhub.com";
    # defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory";

    # uncomment this for acme to generate the ssl certs
    # certs = {
    #   "lamhub.local" = {
    #     webroot = "/var/lib/acme/lamhub.local";
    #   };
    # };
  };
}
