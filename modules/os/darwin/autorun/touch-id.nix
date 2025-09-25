{pkgs, ...}: {
  # https://github.com/LnL7/nix-darwin/pull/787                                                                                                 │
  # security.pam.enableSudoTouchIdAuth = true;

  # Install pam_reattach, in order for touchid works in tmux
  environment.systemPackages = [
    pkgs.pam-reattach
  ];

  # Configure pam_reattach for sudo_local
  security.pam.services.sudo_local.text = ''
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
    auth       sufficient     pam_tid.so
  '';
}
