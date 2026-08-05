# all 'parameterized' / hard-coded / constant values should be placing here
rec {
  # nix config home dir
  myRepoName = "lamt-nixconfig";
  timeZone = "Australia/Sydney";

  # Directory under the secrets repository holding this consumer's material.
  # Change this if the layout in lamt-secrets is renamed or moved. Hosts whose
  # secrets live under another site are resolved by NXD from the repository
  # layout, so they are not listed here.
  secretsSite = "bar";

  # globals
  stateVersion = "23.11";
  defaultUsername = "lamt";

  gitUserName = "LamT";
  gmailDomain = "gmail.com";
  gitUserEmail = "lamtt77@${gmailDomain}";

  githubUser = "lamtt77";
  githubPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  # gpg LamT default-key for signing
  gpgDefaultKey = "C968951468B463F1";
  gpgEncryption = "33C207DE4C1A0CC7";

  # gpg LamT 0xD84F7D726159A16D
  gpgSshKey = "D84F7D726159A16D";
  gpgSshKeygrip = "BF45511ED97F72A80E247CD928B3FF3044A1EC39";

  # openssh authorizedKeys: lamt ssh pubkey
  mySshAuthKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCiBimBlJYNvMmk8F/UPvBjtgBR8tDIgXyeaUOIEtOA lamt";
  # Exact two-field form for identity selectors and protocol contracts that
  # intentionally reject authorized_keys comments.
  mySshAuthPublicKey = builtins.concatStringsSep " " (
    builtins.match "^(ssh-[^ ]+) ([^ ]+).*$" mySshAuthKey
  );

  defaultNetworks = [ "192.168.1.0/24" ];
  myDomain = "lamhub.com";
  teaURL = "tea.${myDomain}";
  teaPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFQNRnyN+YfSLPEnAlHUAocBYRLZuGUOQuJLVJ0beMr";
  hostURL = "air15.lamhub.lan";
  nasIp = "192.168.1.6";
  nasArthurVM = "${nasIp}:/mnt/arthur_z2/VM";

  # postfix
  relayHost = "smtp.zoho.com";
  relayPort = 587;
  infoEmail = "info@${myDomain}";

  # Common networking defaults
  networkingDefaults = {
    gateway = "192.168.1.1";
    netmask = "24";
    nameservers = [ "192.168.1.1" ];
  };

  # Public key corresponding to nix_builder_key in sops secrets.
  # Shared across client hosts to run distributed builds on build machines.
  nixBuilderPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPQ6rLqT/I8ihel6CUfXc3MuVzcr/cG7nLe13XMSKnJj nix-builder";

  # Public trust material for the FCM Harmonia cache. The signing private key
  # and Caddy private CA remain only on fcmbuilder.
  fcmBinaryCache = {
    url = "https://192.168.7.10";
    publicKey = "fcmbuilder:891bx1mdLp7BaGNISedvNgCwXCjwkIwurHknv5kMbtw=";
    caCertificate = builtins.readFile ./nxd/certs/fcmbuilder-root-ca.pem;
  };

  # host-specific configurations
  hosts.avon.nas = nasArthurVM;

  # PVE node addresses and names live in infra/site.nix clusters.
  # Use lib.my.pveNodeAddress / lib.my.pveNode, not defines.hosts.pve*.
}
