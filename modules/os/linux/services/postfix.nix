# reference: https://wiki.centos.org/HowTos(2f)postfix_sasl.html
# usage:
#   25-smtp: no password required for local lan, super unimportant emails only
#   465-smtps and 587-smtp-tls: auth via dovecot

{ inputs, config, lib, pkgs, hostname, ... }:

with lib;
let
  inherit (inputs.self) mydefs;
  cfg = config.modules.os.linux.services.postfix;
  sslServerCert = config.age.secrets."${hostname}/ssl_cert".path;
  sslServerKey = config.age.secrets."${hostname}/ssl_key".path;
  sslCACert = config.age.secrets."${hostname}/ssl_cacert".path;
in {
  options.modules.os.linux.services.postfix = {
    enable = mkEnableOption "";
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ 25 465 587 ];
    age.secrets."${hostname}/sasl_password".owner = "postfix";

    user.packages = with pkgs; [ openssl ];

    # TODO: extract to dovecot module if planned to use imap and pop3
    services.dovecot2 = {
      enable = true;

      inherit sslServerCert sslServerKey sslCACert;

      # auth will be the accessible unix users of dovecot host
      extraConfig = ''
        ssl = required

        service auth {
          unix_listener /var/lib/postfix/queue/private/auth {
            mode = 0660
            user = postfix
            group = postfix
          }
        }
      '';
    };

    services.postfix = {
      enable = true;
      enableSmtp = true;
      enableSubmission = true;
      enableSubmissions = true;

      networks = mydefs.defaultNetworks;

      relayHost = mydefs.relayHost;
      relayPort = mydefs.relayPort;
      rootAlias = mydefs.infoEmail;

      sslCert = sslServerCert;
      sslKey = sslServerKey;

      config = {
        smtp_use_tls = "yes";
        smtp_sasl_auth_enable = "yes";
        smtp_sasl_security_options = "";

        # ref: https://serverfault.com/questions/443652/using-postfix-to-relay-via-multiple-google-apps-accounts
        smtp_sender_dependent_authentication = "yes";
        sender_dependent_relayhost_maps = "texthash:${config.age.secrets."${hostname}/sender_relay".path}";
        smtp_sasl_password_maps = "texthash:${config.age.secrets."${hostname}/sasl_password".path}";

        smtpd_sasl_auth_enable = "yes";
        smtpd_sasl_type = "dovecot";
        # uncomment this if required auth for plain-old smtp too
        # smtpd_client_restrictions = "permit_sasl_authenticated,reject";
        # milter_macro_daemon_name = "ORIGINATING";
      };

      extraConfig = ''
        smtpd_sasl_path = private/auth
        smtpd_sasl_authenticated_header = yes
      '';
    };
  };
}
