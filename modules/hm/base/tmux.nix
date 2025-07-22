{ inputs, config, lib, ... }:

with lib;
let
  cfg = config.modules.hm.base.tmux;
in {
  options.modules.hm.base.tmux = with types; {
    enable = mkEnableOption "Tmux Multiplexer";
  };

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      terminal = "xterm-256color";
      shortcut = "l";
      secureSocket = false;

      extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"

      set -g @dracula-show-battery false
      set -g @dracula-show-network false
      set -g @dracula-show-weather false

      bind -n C-k send-keys "clear"\; send-keys "Enter"
    '';
    };
  };
}
