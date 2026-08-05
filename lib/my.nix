{
  lib,
  mydefs,
  ...
}:
let
  # Pure access to the normalized infra graph (site.hosts and clusters).
  # Host OS modules and packages must use these helpers instead of config.deployment
  # or duplicated defines.nix topology facts.
  infra = import ../infra { inherit lib; };
  inherit (infra) site;
  clusterNodes = builtins.foldl' (
    acc: clusterId:
    acc
    // builtins.listToAttrs (
      map (nodeId: {
        name = nodeId;
        value = site.nodes.${nodeId} // {
          cluster = clusterId;
          endpoint = site.nodes.${nodeId}.address;
        };
      }) site.clusters.${clusterId}.nodes
    )
  ) { } (builtins.attrNames site.clusters);
in
{
  inherit site;

  # Management / deploy address authored only in infra/site.nix site.hosts.
  hostAddress =
    name:
    let
      addr = (site.hosts.${name} or { }).targetIp or "";
    in
    if addr == "" then throw "Host '${name}' has no targetIp in infra/site.nix site.hosts" else addr;

  # Optional address for hosts that may fall back to DHCP when unset.
  hostAddressOr =
    name: default:
    let
      addr = (site.hosts.${name} or { }).targetIp or "";
    in
    if addr == "" then default else addr;

  # PVE node API / management address from infra cluster projection.
  pveNodeAddress =
    nodeId:
    let
      provider = clusterNodes.${nodeId} or null;
    in
    if provider == null then
      throw "Unknown PVE node '${nodeId}' in infra/site.nix clusters"
    else
      provider.endpoint;

  pveNode =
    nodeId:
    let
      provider = clusterNodes.${nodeId} or null;
    in
    if provider == null then
      throw "Unknown PVE node '${nodeId}' in infra/site.nix clusters"
    else
      provider;

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

  # Serialize effective `nix.settings` for a nix.conf fragment (Darwin
  # Determinate path writes this to /etc/nix/nix.custom.conf).
  #
  # Use the merged config attrset only. Do not filter on option `.isDefined`:
  # with `nix.enable = false`, freeform / partially-declared settings often
  # report isDefined=false even when values are present, which dropped
  # trusted-users, substituters, and trusted-public-keys from the conf.
  serializeNixSettings =
    { config }:
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

      # Drop nulls only. Keep empty lists (valid nix.conf values for some keys).
      settings = lib.filterAttrs (_: value: value != null) config.nix.settings;
    in
    lib.generators.toKeyValue { inherit mkKeyValue; } settings;
}
