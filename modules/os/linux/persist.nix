{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.persist;
in
{
  options.persist = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable state persistence for ephemeral systems.";
    };

    persistRoot = mkOption {
      type = types.str;
      default = "/persist";
      description = "Path to the persistent storage root.";
    };

    state = {
      directories = mkOption {
        type = types.listOf (types.either types.str types.attrs);
        default = [ ];
        description = "List of directories to persist.";
      };

      files = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of files to persist.";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.persistence."${cfg.persistRoot}" = {
      enable = true;
      hideMounts = true;
      directories = cfg.state.directories;
      files = cfg.state.files;
    };
  };
}
