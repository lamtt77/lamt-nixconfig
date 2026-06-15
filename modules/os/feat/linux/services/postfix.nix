# reference: https://wiki.centos.org/HowTos(2f)postfix_sasl.html
# usage:
#   25-smtp: no password required for local lan, super unimportant emails only
#   465-smtps and 587-smtp-tls: auth via dovecot
{
  config,
  lib,
  pkgs,
  mydefs,
  myargs,
  ...
}:
with lib;
let
  sslServerCert = config.sops.secrets."ssl_cert".path;
  sslServerKey = config.sops.secrets."ssl_key".path;
  sslCACert = config.sops.secrets."ssl_cacert".path;
in
{
  networking.firewall.allowedTCPPorts = [
    25
    465
    587
  ];
  sops = {
    secrets = {
      # initial secrets
      "sasl_password".owner = "postfix";
      "sender_relay" = { };
      "ssl_cert" = { };
      "ssl_key" = { };
      "ssl_cacert" = { };
    };
  };

  users.users.${myargs.username}.packages = with pkgs; [ openssl ];

  # TODO: extract to dovecot module if planned to use imap and pop3
  services.dovecot2 = {
    enable = true;
    package = pkgs.dovecot_2_4;

    settings = {
      dovecot_config_version = config.services.dovecot2.package.version;
      dovecot_storage_version = config.services.dovecot2.package.version;

      ssl = "required";
      ssl_server_cert_file = "${sslServerCert}";
      ssl_server_key_file = "${sslServerKey}";
      ssl_server_ca_file = "${sslCACert}";

      # auth will be the accessible unix users of dovecot host
      "service auth" = {
        "unix_listener /var/lib/postfix/queue/private/auth" = {
          mode = "0660";
          user = "postfix";
          group = "postfix";
        };
      };
    };
  };

  services.postfix = {
    enable = true;
    enableSmtp = true;
    enableSubmission = true;
    enableSubmissions = true;

    rootAlias = mydefs.infoEmail;

    settings.main = {
      mynetworks = mydefs.defaultNetworks;
      relayhost = [ "[${mydefs.relayHost}]:${toString mydefs.relayPort}" ];

      smtpd_tls_chain_files = [
        sslServerKey
        sslServerCert
      ];

      smtp_tls_security_level = "encrypt";
      smtp_sasl_auth_enable = "yes";
      smtp_sasl_security_options = "";

      # ref: https://serverfault.com/questions/443652/using-postfix-to-relay-via-multiple-google-apps-accounts
      smtp_sender_dependent_authentication = "yes";
      sender_dependent_relayhost_maps = "texthash:${config.sops.secrets."sender_relay".path}";
      smtp_sasl_password_maps = "texthash:${config.sops.secrets."sasl_password".path}";

      smtpd_sasl_auth_enable = "yes";
      smtpd_sasl_type = "dovecot";
      # mynetworks does not require auth
      smtpd_client_restrictions = "permit_mynetworks,permit_sasl_authenticated,reject";
      milter_macro_daemon_name = "ORIGINATING";

      smtpd_sasl_path = "private/auth";
      smtpd_sasl_authenticated_header = "yes";
    };
  };
}
