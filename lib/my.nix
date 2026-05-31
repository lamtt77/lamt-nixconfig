{mydefs, ...}: {
  mkLinkCfg = config: path: config.lib.file.mkOutOfStoreSymlink (config.home.homeDirectory + "/" + mydefs.myRepoName + "/" + path);

  # Function to create static networking config
  mkStaticNetworking = hostCfg: {
    defaultGateway = hostCfg.gateway;
    inherit (hostCfg) nameservers;
    interfaces.${hostCfg.interface} = {
      useDHCP = false;
      ipv4.addresses = [{
        address = hostCfg.ip;
        prefixLength = 24;
      }];
    };
  };
}
