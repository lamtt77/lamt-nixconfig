# this may not work if we use gpg-agent as the default
# Solution: READ: https://unix.stackexchange.com/questions/554153/what-is-the-proper-configuration-for-gpg-ssh-and-gpg-agent-to-use-gpg-auth-sub

{ inputs, pkgs, config, lib, ... }:
let
  hostnames = builtins.attrNames inputs.self.nixosConfigurations;
in
with lib;
{
  config = mkIf config.programs.ssh.enable {
    programs.ssh = {
      # TODO: not working yet
      # matchBlocks = {
      #   net = {
      #     host = builtins.concatStringsSep " " hostnames;
      #     forwardAgent = true;
      #     remoteForwards = [
      #       {
      #         bind.address = let
      #           bindsockset = pkgs.runCommand "gpgconf" {buildInputs = [pkgs.gnupg];} ''
      #           gpgconf --list-dir agent-socket > $out
      #           '';
      #         in ''${bindsockset}'';
      #         host.address = let
      #           hostsockset = pkgs.runCommand "gpgconf" {buildInputs = [pkgs.gnupg];} ''
      #           gpgconf --list-dir agent-extra-socket > $out
      #           '';
      #         in ''${hostsockset}'';
      #       }
      #     ];
      #   };
      # };

      extraConfig = ''
      # a private key used during authentication will be added to the running ssh-agent
      # AddKeysToAgent yes
      # UseKeychain yes

      # Host 192.168.*
      #   # custom identity file: in case of not using the default gpg-agent
      #   IdentityFile ~/.ssh/id_ed25519
      #   # required to prevent sending default identity files first.
      #   IdentitiesOnly yes

      Host 192.168.1.8
        HostName 192.168.1.8
        User ubuntu
        ForwardAgent yes

      Host 192.168.1.32
        HostName 192.168.1.32
        User ubuntu
        ForwardAgent yes

      Host 192.168.1.36
        HostName 192.168.1.36
        User stack
        ForwardAgent yes
    '';
    };

  };
}
