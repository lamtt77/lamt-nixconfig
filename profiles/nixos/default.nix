# Goal: use as few modules and packages as possible
{
  pkgs,
  my,
  ...
}:
let
  profileFeatures = [
    ../../modules/hm/feat/bash.nix
    ../../modules/hm/feat/term/tmux.nix
    ../../modules/hm/feat/pass.nix
    {
      module = ../../modules/hm/feat/gnupg.nix;
      args = {
        enableSSHSupport = true;
      };
    }
  ];
in
{
  imports = my.resolveFeatures profileFeatures;

  programs.fzf.enable = true;

  home.packages = with pkgs; [
    jq
    lsof
    iftop
    iperf
    htop
    tcpdump
    yazi
  ];
}
