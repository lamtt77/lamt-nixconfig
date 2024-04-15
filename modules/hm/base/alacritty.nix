{ config, lib, ... }:

with lib;
let
  cfg = config.modules.hm.base.alacritty;
in {
  options.modules.hm.base.alacritty = with types; {
    enable = mkEnableOption "Alacritty shell";
  };

  config = mkIf cfg.enable {
    programs.alacritty = {
      enable = true;

      settings = {
        env.TERM = "xterm-256color";

        key_bindings = [
          { key = "K"; mods = "Command"; chars = "ClearHistory"; }
          { key = "V"; mods = "Command"; action = "Paste"; }
          { key = "C"; mods = "Command"; action = "Copy"; }
          { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
          { key = "Equals"; mods = "Command"; action = "IncreaseFontSize"; }
          { key = "Minus"; mods = "Command"; action = "DecreaseFontSize"; }
        ];
      };
    };
  };
}
