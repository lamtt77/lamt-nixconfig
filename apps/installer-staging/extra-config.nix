{ pkgs, ...}:
{
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
      "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      "tea.lamhub.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIODyGjuq0vFxJVimNtVhYgVQqmCLNPQHCwJm9tvfSfja";
    };
  };

  programs.ssh.startAgent = true;

  # TODO harded-code here because there is no inputs when calling from /etc/nixos/configuration.nix
  users.users.root = {
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCiBimBlJYNvMmk8F/UPvBjtgBR8tDIgXyeaUOIEtOA lamt" ];
  };
}
