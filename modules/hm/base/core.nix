{ inputs, config, lib, pkgs, username, isWSL, ... }:

let
  stateVersion = inputs.self.mydefs.stateVersion;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  home = {
    inherit stateVersion username;

    homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
    activation.report-changes = config.lib.dag.entryAnywhere ''
      ${pkgs.nvd}/bin/nvd diff $oldGenPath $newGenPath'';
  };

  # make cursor not tiny on hidpi screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
    x11.enable = true;
  };
}
