{pkgs, ...}: {
  modules.hm.base.bash.enable = true;
  modules.hm.base.term.tmux.enable = true;

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
