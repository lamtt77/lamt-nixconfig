{ lib }:
let
  hostsDir = ../hosts;
  siteEvaluation = lib.evalModules {
    modules = [
      ./options.nix
      { site = import ./site.nix; }
    ];
  };
  rawSite = siteEvaluation.config.site;
  clusterProviders = builtins.foldl' (
    acc: clusterId:
    let
      cluster = rawSite.clusters.${clusterId};
      nodeProviders = builtins.listToAttrs (
        map (nodeId: {
          name = nodeId;
          value =
            let
              node = rawSite.nodes.${nodeId};
            in
            {
              endpoint = node.address;
              cluster = clusterId;
              node = node.proxmoxNodeName;
              inherit (node)
                defaultIsoStorage
                defaultDiskStorage
                defaultGateway
                defaultNetwork
                defaultDiscoverySubnets
                ;
            };
        }) cluster.nodes
      );
    in
    acc // nodeProviders
  ) { } (builtins.attrNames rawSite.clusters);
  site = rawSite;

  evalOptions = lib.evalModules {
    modules = [ ../hosts/meta-options.nix ];
  };
  defaultDeployment = evalOptions.config.deployment;
  defaultBinaryCache = evalOptions.config.nxd.binaryCache;

  recursiveMerge =
    lhs: rhs:
    if builtins.isAttrs lhs && builtins.isAttrs rhs then
      builtins.listToAttrs (
        map (name: {
          inherit name;
          value = if builtins.hasAttr name rhs then recursiveMerge lhs.${name} rhs.${name} else lhs.${name};
        }) (builtins.attrNames lhs)
      )
    else
      rhs;

  roleDefaults = import ../flake/host-roles.nix;

  loadHostMeta =
    name:
    let
      meta = import (hostsDir + "/${name}/meta.nix");
      hostInfra = site.hosts.${name} or { };
      role = meta.role or null;
      hasRole = role != null && builtins.hasAttr role roleDefaults;
      roleDefault = if hasRole then roleDefaults.${role} else { };
      getValue =
        key: default:
        if builtins.hasAttr key meta then
          meta.${key}
        else if builtins.hasAttr key roleDefault then
          roleDefault.${key}
        else
          default;
      buildSystem = getValue "buildSystem" true;
      roleDeployment = roleDefault.deployment or { };
      mergedDeployment = recursiveMerge (recursiveMerge defaultDeployment roleDeployment) (
        meta.deployment or { }
      );
      providerId = mergedDeployment.proxmox.provider;
      provider =
        if providerId == "" then
          null
        else
          clusterProviders.${providerId}
            or (throw "Host '${name}' references unknown PVE provider '${providerId}'");
      resolvedProxmox =
        mergedDeployment.proxmox
        // lib.optionalAttrs (provider != null) {
          host = provider.endpoint;
          node = provider.node;
          diskStorage =
            if mergedDeployment.proxmox.diskStorage == "" then
              provider.defaultDiskStorage
            else
              mergedDeployment.proxmox.diskStorage;
          iso = mergedDeployment.proxmox.iso // {
            storage =
              if mergedDeployment.proxmox.iso.storage == "" then
                provider.defaultIsoStorage
              else
                mergedDeployment.proxmox.iso.storage;
          };
          net0 =
            if mergedDeployment.proxmox.net0 == "" then
              provider.defaultNetwork
            else
              mergedDeployment.proxmox.net0;
          discoverySubnets =
            if mergedDeployment.proxmox.discoverySubnets == [ ] then
              provider.defaultDiscoverySubnets
            else
              mergedDeployment.proxmox.discoverySubnets;
          bootstrap = mergedDeployment.proxmox.bootstrap // {
            gateway =
              if mergedDeployment.proxmox.bootstrap.gateway == "" then
                provider.defaultGateway
              else
                mergedDeployment.proxmox.bootstrap.gateway;
          };
        };
      requestedBinaryCache = (meta.nxd or { }).binaryCache or defaultBinaryCache;
      # A build machine builds its own system: taking the site builder would
      # make it import its whole closure from a machine it cannot substitute
      # from. NXD resolves the builder by target alias, so no address is needed.
      automaticBuilder =
        if role == "builder" then
          "${meta.username or "nixos"}@${name}"
        else
          site.defaults.builderBySystem.${meta.system} or "";
      resolvedBinaryCache =
        if requestedBinaryCache == null then
          null
        else
          recursiveMerge defaultBinaryCache requestedBinaryCache;
      resolvedDeployment = mergedDeployment // {
        targetIp = hostInfra.targetIp or mergedDeployment.targetIp;
        sshIdentityPublicKey =
          if mergedDeployment.sshIdentityPublicKey == "" then
            site.defaults.sshIdentityPublicKey
          else
            mergedDeployment.sshIdentityPublicKey;
        builder = if mergedDeployment.builder == "" then automaticBuilder else mergedDeployment.builder;
        tailscaleNamespace =
          if mergedDeployment.tailscaleNamespace == "" then
            site.defaults.tailscaleNamespace
          else
            mergedDeployment.tailscaleNamespace;
        proxmox = resolvedProxmox;
        vmware = mergedDeployment.vmware // {
          isoDirectory =
            if mergedDeployment.vmware.isoDirectory == "" then
              site.vmware.isoDirectory
            else
              mergedDeployment.vmware.isoDirectory;
        };
      };
      validatedHostOptions = lib.evalModules {
        modules = [
          ../hosts/meta-options.nix
          {
            disposable = meta.disposable or false;
            user = meta.username or "nixos";
            nxd.binaryCache = resolvedBinaryCache;
            nxd.secretsSite = lib.mkIf ((meta.nxd or { }) ? secretsSite) meta.nxd.secretsSite;
            deployment = resolvedDeployment;
          }
        ];
      };
      roleTags = roleDefault.tags or [ ];
      metaTags = meta.tags or [ ];
      implicitTag = if role != null then [ role ] else [ ];
      finalTags = lib.unique (implicitTag ++ roleTags ++ metaTags);
      roleOSFeatures = roleDefault.osFeatures or [ ];
      roleHMFeatures = roleDefault.hmFeatures or [ ];
      osFeatures = lib.unique (roleOSFeatures ++ (meta.osFeatures or [ ]));
      hmFeatures = lib.unique (roleHMFeatures ++ (meta.hmFeatures or [ ]));
    in
    assert lib.assertMsg (!((meta.deployment or { }) ? targetIp))
      "Host '${name}' declares deployment.targetIp; declare host IPs in infra/site.nix site.hosts instead";
    assert lib.assertMsg (role == null || hasRole) "Host '${name}' has unknown role '${toString role}'";
    assert lib.assertMsg (!buildSystem || role != null) "Buildable host '${name}' must declare a role";
    {
      class = meta.class;
      system = meta.system;
      user = meta.username or "nixos";
      disposable = validatedHostOptions.config.disposable;
      inherit
        role
        buildSystem
        osFeatures
        hmFeatures
        ;
      tags = finalTags;
      server = getValue "server" false;
      wsl = getValue "wsl" false;
      hasDisko = getValue "hasDisko" false;
      home = getValue "home" false;
      cross = meta.cross or null;
      deployment = validatedHostOptions.config.deployment // {
        # Cache policy has one authoring source. NXD's installer projection is
        # derived from the same host value used by the installed system.
        binaryCache = validatedHostOptions.config.nxd.binaryCache;
      };
      nxd = {
        binaryCache = validatedHostOptions.config.nxd.binaryCache;
        secretsSite = validatedHostOptions.config.nxd.secretsSite;
      };
      features = osFeatures ++ hmFeatures;
    };

  hostDirectories = builtins.attrNames (
    lib.filterAttrs (name: type: type == "directory" && !(lib.hasPrefix "_" name)) (
      builtins.readDir hostsDir
    )
  );

  hostMeta = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = loadHostMeta name;
    }) (builtins.filter (name: builtins.pathExists (hostsDir + "/${name}/meta.nix")) hostDirectories)
  );
  invalidPveHosts = lib.filterAttrs (
    _name: meta:
    let
      proxmox = meta.deployment.proxmox;
    in
    proxmox.provider != ""
    && (
      !(builtins.hasAttr proxmox.provider clusterProviders)
      || clusterProviders.${proxmox.provider}.node != proxmox.node
      || clusterProviders.${proxmox.provider}.endpoint != proxmox.host
    )
  ) hostMeta;

in
assert lib.assertMsg (
  invalidPveHosts == { }
) "LAMT host Proxmox provider, node, and endpoint references must match site inventory";
{
  inherit
    site
    hostMeta
    ;
}
