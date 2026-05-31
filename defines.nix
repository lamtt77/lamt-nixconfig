# all 'parameterized' / hard-coded / constant values should be placing here
rec {
  # nix config home dir
  myRepoName = "lamt-nixconfig";
  timeZone = "Australia/Sydney";

  # globals
  stateVersion = "23.11";
  defaultUsername = "lamt";
  systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

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

  defaultNetworks = ["192.168.1.0/24"];
  myDomain = "lamhub.com";
  teaURL = "tea.${myDomain}";
  teaPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFQNRnyN+YfSLPEnAlHUAocBYRLZuGUOQuJLVJ0beMr";
  hostURL = "air15.lamhub.lan";
  nas = "nas.lamhub.me";
  nasBackupDevice = "${nas}:/mnt/arthur_z2/Backup";
  nasArthurVM = "${nas}:/mnt/arthur_z2/VM";

  # postfix
  relayHost = "smtp.zoho.com";
  relayPort = 587;
  infoEmail = "info@${myDomain}";

  # Common networking defaults
  networkingDefaults = {
    gateway = "192.168.1.1";
    netmask = "24";
    nameservers = ["192.168.1.1"];
  };

  # networking configurations per host
  networking = {
    avon =
      networkingDefaults
      // {
        ip = "192.168.1.18";
        interface = "ens18";
        iperfPort = 5201;
      };
    utils =
      networkingDefaults
      // {
        ip = "192.168.1.19";
        interface = "ens18";
      };
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
