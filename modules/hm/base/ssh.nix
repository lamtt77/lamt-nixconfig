# this may not work if we use gpg-agent as the default

{ ... }:

{
  programs.ssh = {
    enable = true;

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
}
