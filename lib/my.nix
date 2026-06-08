{
  lib,
  mydefs,
  ...
}:
{
  mkLinkCfg =
    config: path:
    config.lib.file.mkOutOfStoreSymlink (
      config.home.homeDirectory + "/" + mydefs.myRepoName + "/" + path
    );

  # Function to create static networking config
  mkStaticNetworking = hostCfg: {
    defaultGateway = hostCfg.gateway;
    inherit (hostCfg) nameservers;
    interfaces.${hostCfg.interface} = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = hostCfg.ip;
          prefixLength = 24;
        }
      ];
    };
  };

  # Serialize nix.settings to a string format compatible with nix.conf,
  # filtering out any options that are declared but not defined when nix.enable = false.
  serializeNixSettings =
    {
      config,
      options,
    }:
    let
      mkKeyValue =
        k: v:
        let
          toStr =
            x:
            if builtins.isBool x then
              (if x then "true" else "false")
            else if builtins.isList x then
              builtins.concatStringsSep " " (map toStr x)
            else
              toString x;
        in
        "${k} = ${toStr v}";

      subOptions = options.nix.settings.type.getSubOptions [ ];
      isSettingDefined = name: if subOptions ? ${name} then subOptions.${name}.isDefined else true;
      definedSettingsList = builtins.filter isSettingDefined (builtins.attrNames config.nix.settings);
      definedSettings = lib.genAttrs definedSettingsList (name: config.nix.settings.${name});
    in
    lib.generators.toKeyValue { inherit mkKeyValue; } definedSettings;
}
