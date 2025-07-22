{ pkgs, ...}: let
  # there is no inputs when calling from /etc/nixos/configuration.nix
  # note that the current dir in this case should be /etc/nixos, a bit hacky :)
  mydefs = import ./defines.nix;
in {
  # create zram swap now, so it will be ready after the 1st reboot
  imports = [ ./zramswap.nix ];

  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  environment.systemPackages = with pkgs; [
    rsync
    gitMinimal
    vim
  ];

  nix.settings = {
    experimental-features = "nix-command flakes";
    auto-optimise-store = true;
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    knownHosts = {
      "github.com".publicKey = mydefs.githubPubkey;
      "tea.lamhub.com".publicKey = mydefs.teaPubkey;
    };
  };

  programs.ssh.startAgent = true;

  users.users.root = {
    openssh.authorizedKeys.keys = [ "${mydefs.mySshAuthKey}" ];
  };
}
