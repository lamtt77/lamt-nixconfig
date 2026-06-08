# all 'parameterized' / hard-coded / constant values should be placing here
rec {
  # nix config home dir
  myRepoName = "lamt-nixconfig";
  timeZone = "Australia/Sydney";

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

  # host-specific configurations
  hosts.avon.nas = nasArthurVM;

  hosts.pve1 = {
    hostname = "pve1";
    ip = "192.168.1.15";
  };

  hosts.pve2 = {
    hostname = "pve2";
    ip = "192.168.1.5";
  };
}
