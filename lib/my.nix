{mydefs, ...}: {
  mkLinkCfg = config: path: config.lib.file.mkOutOfStoreSymlink (config.home.homeDirectory + "/" + mydefs.myRepoName + "/" + path);
}
