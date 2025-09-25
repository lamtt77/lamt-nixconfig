# Goal: use as less modules and packages as possible
{pkgs, ...}: {
  modules.hm.base.bash.enable = true;
  modules.hm.base.term.tmux.enable = true;

  modules.hm.base.pass.enable = true;
  modules.hm.base.gnupg.enable = true;

  programs.fzf.enable = true;

  home.packages = with pkgs; [
    lsof
    iftop
    iperf
    htop
    tcpdump

    ranger
    highlight

    borgbackup
    rclone
    restic

    ookla-speedtest
  ];
}
