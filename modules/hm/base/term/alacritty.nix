{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.hm.base.term.alacritty;
in
{
  options.modules.hm.base.term.alacritty = with types; {
    enable = mkEnableOption "Alacritty shell";
  };

  config = mkIf cfg.enable {
    programs.alacritty = {
      enable = true;

      settings = {
        env.TERM = "xterm-256color";

        window = {
          decorations = "transparent";
        };

        cursor.style = "Block";

        font =
          if pkgs.stdenv.isDarwin then
            {
              normal = {
                family = "Monaco Nerd Font Mono";
              };
              size = 15;
            }
          else
            {
              normal = {
                family = "Liberation Mono";
              };
              size = 12;
            };

        keyboard.bindings = [
          {
            key = "K";
            mods = "Command";
            chars = "ClearHistory";
          }
          {
            key = "V";
            mods = "Command";
            action = "Paste";
          }
          {
            key = "C";
            mods = "Command";
            action = "Copy";
          }
          {
            key = "Key0";
            mods = "Command";
            action = "ResetFontSize";
          }
          {
            key = "Equals";
            mods = "Command";
            action = "IncreaseFontSize";
          }
          {
            key = "Minus";
            mods = "Command";
            action = "DecreaseFontSize";
          }
        ];
      };
    };
  };
}
