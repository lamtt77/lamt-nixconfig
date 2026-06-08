{ pkgs, ... }:
let
  # there is no inputs when calling from /etc/nixos/configuration.nix
  # note that the current dir in this case should be /etc/nixos, a bit hacky :)
  mydefs = import ./defines.nix;
in
{
  # create zram swap now, so it will be ready after the 1st reboot
  imports = [
    ./zramswap.nix
    ./bootloader.nix
  ];

  boot = {
    # Be careful updating this.
    kernelPackages = pkgs.linuxPackages_latest;
  };

  environment.systemPackages = with pkgs; [
    git
    jq
    rsync
    vim
  ];

  nix.settings = {
    experimental-features = "nix-command flakes";
  };

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "yes";
    knownHosts = {
      "github.com".publicKey = mydefs.githubPubkey;
      "${mydefs.teaURL}".publicKey = mydefs.teaPubkey;
    };
  };

  programs.ssh.startAgent = true;

  users.users.root = {
    openssh.authorizedKeys.keys = [ "${mydefs.mySshAuthKey}" ];
  };
}
