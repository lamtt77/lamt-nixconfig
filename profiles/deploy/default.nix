{pkgs, ...}: {
  modules.hm.base.bash.enable = true;
  modules.hm.base.term.tmux.enable = true;

  modules.hm.base.pass.enable = true;
  modules.hm.base.gnupg.enable = true;
  modules.hm.base.gnupg.enableSSHSupport = true;

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
