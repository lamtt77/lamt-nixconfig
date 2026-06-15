{
  config,
  lib,
  pkgs,
  ...
}:
{
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
}
