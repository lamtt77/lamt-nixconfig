{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.hm.base.editors.zed;
in
{
  options = with types; {
    modules.hm.base.editors.zed = {
      enable = mkEnableOption "Zed Editor";
    };
  };

  config = mkIf cfg.enable {
    programs.zed-editor = {
      enable = true;

      extensions = [
        "biome"
      ];

      userSettings = {
        theme = "Ayu Dark";

        autosave = "on_focus_change";

        formatter = {
          language_server.name = "biome";
        };

        code_actions_on_format = {
          "source.fixAll.biome" = true;
          "source.organizeImports.biome" = true;
        };

        inlay_hints.enabled = true;

        indent_guides.coloring = "indent_aware";

        telemetry = {
          diagnostics = false;
          metrics = false;
        };
      };
    };
  };
}
