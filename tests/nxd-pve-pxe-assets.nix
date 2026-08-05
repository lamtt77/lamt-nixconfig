let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  pve1Answer = builtins.readFile ../infra/proxmox/pxe/targets/pve1/answer.toml;
  pve2Answer = builtins.readFile ../infra/proxmox/pxe/targets/pve2/answer.toml;
  pveTestAnswer = builtins.readFile ../infra/proxmox/pxe/targets/pve-test/answer.toml;
  pveTestMeta = import ../hosts/pve-test/meta.nix;

  # Test assertions
  runTests = {
    testPve1 = {
      expr =
        lib.hasInfix "fqdn = \"pve1.lamhub.com\"" pve1Answer
        && lib.hasInfix "disk-list = [ \"sda\", \"sdb\" ]" pve1Answer
        && lib.hasInfix "cidr = \"192.168.1.15/24\"" pve1Answer
        && builtins.pathExists ../infra/proxmox/state/pve/pve1/etc/network/interfaces
        && builtins.pathExists ../infra/proxmox/state/pve/pve1/etc/multipath.conf;
      expected = true;
    };
    testPve2 = {
      expr =
        lib.hasInfix "fqdn = \"pve2.lamhub.com\"" pve2Answer
        && lib.hasInfix "disk-list = [ \"nvme0n1\" ]" pve2Answer
        && lib.hasInfix "cidr = \"192.168.1.5/24\"" pve2Answer
        && builtins.pathExists ../infra/proxmox/state/pve/pve2/etc/network/interfaces;
      expected = true;
    };
    testPveTest = {
      expr =
        lib.hasInfix "fqdn = \"pve-test.lamhub.com\"" pveTestAnswer
        && lib.hasInfix "disk-list = [ \"vda\" ]" pveTestAnswer
        && lib.hasInfix "source = \"from-dhcp\"" pveTestAnswer
        && builtins.pathExists ../infra/proxmox/state/pve/pve-test/etc/network/interfaces;
      expected = true;
    };
    testRestoreIsolation = {
      # Normal node-install state never contains pmxcfs cluster state. The
      # reviewed copies remain separately classified as recovery inputs.
      expr =
        !(builtins.pathExists ../infra/proxmox/state/pve/pve1/etc/pve)
        && !(builtins.pathExists ../infra/proxmox/state/pve/pve2/etc/pve)
        && !(builtins.pathExists ../infra/proxmox/state/pve/pve-test/etc/pve)
        && builtins.pathExists ../infra/proxmox/recovery/pve/barcluster/corosync.conf.in
        && builtins.pathExists ../infra/proxmox/recovery/pve/barcluster/storage.cfg.in;
      expected = true;
    };
    testPveTestDeploymentMeta = {
      # Verify pve-test VM ID and isolated bridges configuration
      expr =
        pveTestMeta.deployment.vmid == "911"
        && pveTestMeta.deployment.proxmox.net0 == "virtio,bridge=vmbrPxe"
        && lib.all (
          net: lib.hasInfix "bridge=vmbrPxe" net || lib.hasInfix "bridge=vmbrTestWan" net
        ) pveTestMeta.deployment.proxmox.extraNetworks;
      expected = true;
    };
  };

  results = lib.mapAttrs (
    name: test: if test.expr == test.expected then "PASSED" else throw "TEST FAILED: ${name}"
  ) runTests;
in
results
