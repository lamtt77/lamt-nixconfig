{
  pkgs,
  my,
  ...
}:
let
  profileFeatures = [
    ../../modules/hm/feat/bash.nix
    ../../modules/hm/feat/term/tmux.nix
    # LamT: nxd is not needed on remote builder
    # ../../modules/hm/feat/nxd.nix
  ];
in
{
  imports = my.resolveFeatures profileFeatures;

  programs.fzf.enable = true;

  home.packages = with pkgs; [
    lsof
    iftop
    iperf
    htop
    tcpdump

    yazi
  ];
}
