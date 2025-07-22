# all 'parameterized' / hard-coded / constant values should be placing here

rec {
  # nix config home dir
  myRepoName = "lamt-nixconfig";
  timeZone = "Australia/Sydney";

  # globals
  stateVersion = "23.11";
  defaultUsername = "lamt";
  systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

  gitUserName = "LamT";
  gmailDomain = "gmail.com";
  gitUserEmail = "lamtt77@${gmailDomain}"; # hide from auto-bot

  githubUser = "lamtt77";
  githubPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  # gpg LamT default-key for signing
  gpgDefaultKey = "C968951468B463F1";
  gpgEncryption = "33C207DE4C1A0CC7";

  # gpg LamT 0xD84F7D726159A16D
  gpgSshKey = "D84F7D726159A16D";
  gpgSshKeygrip = "BF45511ED97F72A80E247CD928B3FF3044A1EC39";
  # gpg LamT old 0x38B165651C99D88D
  # gpgSshKeygrip-old = "5DCD8883C43C139709EF5BB84A85C0A24623A97E";

  # openssh authorizedKeys: lamt ssh pubkey
  mySshAuthKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCiBimBlJYNvMmk8F/UPvBjtgBR8tDIgXyeaUOIEtOA lamt";

  defaultNetworks = ["192.168.1.0/24"];
  myDomain = "lamhub.com";
  teaURL = "tea.${myDomain}";
  teaPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIODyGjuq0vFxJVimNtVhYgVQqmCLNPQHCwJm9tvfSfja";
  # hostURL = "air15.lamhub.local";
  hostURL = "172.16.138.1";
  nas = "nas.lamhub.local";
  nasBackupDevice = "${nas}:/mnt/arthur_z2/Backup";

  # postfix
  relayHost = "smtp.zoho.com";
  relayPort = 587;
  infoEmail = "info@${myDomain}";
}
