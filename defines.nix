# all 'parameterized' / hard-coded / constant values should be placing here
{
  # nix-config home dir
  myRepoName = "lamt-nixos-config";
  hostip = "172.16.138.1";
  timeZone = "Australia/Sydney";

  # globals
  stateVersion = "23.11";
  defaultUsername = "lamt";
  systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

  # gpg LamT default-key for signing
  gpg-default-key = "0xC968951468B463F1";

  # gpg LamT 0xD84F7D726159A16D
  gpg-sshKeys = "BF45511ED97F72A80E247CD928B3FF3044A1EC39";
  # gpg LamT old 0x38B165651C99D88D
  # gpg-sshKeys-old = "5DCD8883C43C139709EF5BB84A85C0A24623A97E";

  # openssh authorizedKeys: lamt ssh pubkey
  ssh-authorizedKeys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCiBimBlJYNvMmk8F/UPvBjtgBR8tDIgXyeaUOIEtOA lamt"];
}
