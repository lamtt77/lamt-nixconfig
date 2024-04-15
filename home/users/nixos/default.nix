{ pkgs, ... }:

{
  modules.hm.base.bash.enable = true;

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
