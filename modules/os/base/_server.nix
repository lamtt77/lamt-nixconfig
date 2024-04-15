{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.bash;

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "acme@lamhub.com";
  # security.acme.defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory";
}
