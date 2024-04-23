# Goal: use as less modules and packages as possible

{ pkgs, ... }:

{
  modules.hm.base.bash.enable = true;
  modules.hm.base.tmux.enable = true;

  modules.hm.base.pass.enable = true;
  modules.hm.base.gnupg.enable = true;

  programs.fzf.enable = true;

  home.packages = with pkgs; [
    htop
    ranger highlight

    borgbackup
    rclone
    restic
  ];
}
