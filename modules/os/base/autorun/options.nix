# customized from hlissner-dotfiles
{ inputs, config, options, lib, username, ... }:

with lib;
let
  mkOpt  = type: default:
    mkOption { inherit type default; };

  mkOpt' = type: default: description:
    mkOption { inherit type default description; };

  inherit (inputs) self;
  # is this combined home-manager mode?
  isCombinedHM = options ? home-manager;
  myRepoName = self.mydefs.myRepoName;
in {
  options = with types; {
    user = mkOpt attrs {};

    dotfiles = {
      dir = mkOpt path
        (removePrefix "/mnt"
          (findFirst pathExists (toString "${self}") [
            "/mnt/${username}/${myRepoName}"
          ]));
      binDir     = mkOpt path "${config.dotfiles.dir}/bin";
      configDir  = mkOpt path "${config.dotfiles.dir}/config";
      modulesDir = mkOpt path "${config.dotfiles.dir}/modules";
      themesDir  = mkOpt path "${config.dotfiles.modulesDir}/themes";
    };

    env = mkOption {
      type = attrsOf (oneOf [ str path (listOf (either str path)) ]);
      apply = mapAttrs
        (n: v: if isList v
               then concatMapStringsSep ":" (x: toString x) v
               else (toString v));
      default = {};
      description = "TODO";
    };

    home = {
      activation = mkOpt attrs {};
      file       = mkOpt' attrs {} "Files to place directly in $HOME";
      configFile = mkOpt' attrs {} "Files to place in $XDG_CONFIG_HOME";
      dataFile   = mkOpt' attrs {} "Files to place in $XDG_DATA_HOME";
    };
  };

  config = {
    users.users.${username} = mkAliasDefinitions options.user;

    # must already begin with pre-existing PATH. Also, can't use binDir here,
    # because it contains a nix store path.
    env.PATH = [ "$DOTFILES_BIN" "$XDG_BIN_HOME" "$PATH" ];

    environment.extraInit =
      concatStringsSep "\n"
        (mapAttrsToList (n: v: "export ${n}=\"${v}\"") config.env);
  } // optionalAttrs (isCombinedHM) {
    # Install user packages to /etc/profiles instead. Necessary for nixos-rebuild build-vm to work.
    #   home.file        ->  home-manager.users.{username}.home.file
    #   home.activation  ->  home-manager.users.{username}.home.activation
    #   home.configFile  ->  home-manager.users.{username}.home.xdg.configFile
    #   home.dataFile    ->  home-manager.users.{username}.home.xdg.dataFile
    home-manager.users.${username} = {
      home = {
        file = mkAliasDefinitions options.home.file;
        activation = mkAliasDefinitions options.home.activation;
      };
      xdg = {
        configFile = mkAliasDefinitions options.home.configFile;
        dataFile   = mkAliasDefinitions options.home.dataFile;
      };
    };
  };
  # REVIEW: add condition for isStandaloneHM
}
