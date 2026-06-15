{
  pkgs,
  lib,
  myargs,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
in
{
  home.packages =
    with pkgs;
    [
      doctl
      borgbackup
      rclone
      restic
    ]
    ++ lib.optionals (isLinux && !myargs.wsl) [
      awscli2
      ssm-session-manager-plugin
      aws-iam-authenticator
      eksctl
    ];
}
