{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.hm.base.term.tmux;
in {
  options.modules.hm.base.term.tmux = with types; {
    enable = mkEnableOption "Tmux Multiplexer";
  };

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      shortcut = "l";
      secureSocket = false;

      plugins = with pkgs; [
        tmuxPlugins.resurrect
        tmuxPlugins.continuum
        {
          plugin = tmuxPlugins.catppuccin;
          extraConfig = ''
            set -g @catppuccin_flavour 'mocha'
            set -g @catppuccin_window_tabs_enabled on
            set -g @catppuccin_date_time "%H:%M"
            set -g @catppuccin_user "off"
            set -g @catppuccin_host "off"
          '';
        }
      ];

      extraConfig = ''
        # Fix escape-time for better Neovim responsiveness
        set-option -sg escape-time 10

        # Enable focus events for autoread
        set-option -g focus-events on

        set -g allow-passthrough on

        set -ga terminal-overrides ",*256col*:Tc"

        # Use vi keybindings
        set -g mode-keys vi
        set -g status-keys vi

        # Smart status management - hide when Neovim is running
        set -g status off
        bind s set -g status
        bind S if-shell 'pgrep -f "nvim"' 'set -g status on' 'set -g status off'

        # Session persistence
        set -g @continuum-restore 'on'
        set -g @resurrect-strategy-nvim 'session'

        # Seamless navigation with vim-tmux-navigator (using M-h/j/k/l)
        is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
        bind -n M-h if-shell "$is_vim" "send-keys M-h" "select-pane -L"
        bind -n M-j if-shell "$is_vim" "send-keys M-j" "select-pane -D"
        bind -n M-k if-shell "$is_vim" "send-keys M-k" "select-pane -U"
        bind -n M-l if-shell "$is_vim" "send-keys M-l" "select-pane -R"
        bind -n M-\\ if-shell "$is_vim" "send-keys M-\\\\" "select-pane -l"
      '';
    };
  };
}
