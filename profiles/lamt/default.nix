{
  lib,
  pkgs,
  my,
  myargs,
  ...
}:
let
  inherit (myargs)
    darwin
    wsl
    role
    ;
  profileFeatures = [
    ../../modules/hm/feat/bash.nix
    ../../modules/hm/feat/zsh.nix
    ../../modules/hm/feat/term/tmux.nix
    ../../modules/hm/feat/term/zellij.nix
    ../../modules/hm/feat/term/alacritty.nix
    ../../modules/hm/feat/term/kitty.nix
    ../../modules/hm/feat/git.nix
    ../../modules/hm/feat/direnv.nix
    # nxd CLI: use local Cargo debug binary for development (export NXD=…/target/debug/nxd).
    # Keeping pkgs.nxd in HM forces a long nxd-0.1.0 rebuild on every switch when the nxd
    # flake input moves. Re-enable for a stable installed CLI after release pins settle.
    # ../../modules/hm/feat/nxd.nix
    {
      module = ../../modules/hm/feat/pass.nix;
      args = { };
    }
    {
      module = ../../modules/hm/feat/gnupg.nix;
      args = {
        enableSSHSupport = true;
      };
    }
    ../../modules/hm/feat/yt-dlp.nix
    ../../modules/hm/feat/editors/helix.nix
    ../../modules/hm/feat/editors/vscode.nix
    {
      module = ../../modules/hm/feat/editors/neovim.nix;
      args = { };
    }
    ../../modules/hm/feat/tools/yazi.nix

    ./sysadmin.nix
  ]
  ++ lib.optional (role == "workstation") ./dev.nix
  ++ lib.optional (role == "workstation" || role == "server") ./cloud.nix
  ++ lib.optional (!darwin) ../../modules/hm/feat/term/ghostty.nix
  ++ lib.optional (!darwin && role != "wsl") ../../modules/hm/feat/term/foot.nix
  ++ lib.optional (!darwin) ../../modules/hm/feat/lang/cc.nix
  ++ lib.optional (!darwin) ../../modules/hm/feat/linux/polkit.nix;
in
{
  imports = my.resolveFeatures profileFeatures;

  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;
    };
    fzf.enable = true;
    man.enable = true;

    go.enable = true;
    yazi.enable = true;
  };
}
