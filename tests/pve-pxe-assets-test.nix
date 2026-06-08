let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  mydefs = import ../defines.nix;
  targets = import ../pkgs/pve-pxe-assets/targets.nix mydefs;
  pveTestMeta = import ../hosts/pve-test/meta.nix;

  # Test assertions
  runTests = {
    testPve1 = {
      expr =
        targets.pve1.hostname == "pve1"
        && targets.pve1.proxmoxNode == "pve-dl360p"
        && targets.pve1.finalIp == "192.168.1.15"
        && lib.elem "sda" targets.pve1.disks
        && lib.elem "sdb" targets.pve1.disks
        && targets.pve1.includeClusterStorage
        && !targets.pve1.requiresRefind;
      expected = true;
    };
    testPve2 = {
      expr =
        targets.pve2.hostname == "pve2"
        && targets.pve2.proxmoxNode == "pve2"
        && targets.pve2.finalIp == "192.168.1.5"
        && lib.elem "nvme0n1" targets.pve2.disks
        && targets.pve2.includeClusterStorage
        && targets.pve2.requiresRefind;
      expected = true;
    };
    testPveTest = {
      expr =
        targets.pve-test.hostname == "pve-test"
        && targets.pve-test.proxmoxNode == "pve-test"
        && targets.pve-test.finalIp == "192.168.250.10"
        && targets.pve-test.autoBoot
        && targets.pve-test.installerNetworkSource == "from-dhcp"
        && builtins.isBool targets.pve-test.serialConsole
        && lib.elem "vda" targets.pve-test.disks
        && !targets.pve-test.includeClusterStorage
        && !targets.pve-test.requiresRefind;
      expected = true;
    };
    testRestoreIsolation = {
      # Verify that pve-test config does not contain corosync or storage configuration
      expr =
        !(builtins.pathExists ../pkgs/pve-pxe-assets/configs/pve-test/etc/pve/corosync.conf)
        && !(builtins.pathExists ../pkgs/pve-pxe-assets/configs/pve-test/etc/pve/storage.cfg);
      expected = true;
    };
    testPveTestDeploymentMeta = {
      # Verify pve-test VM ID and isolated bridges configuration
      expr =
        pveTestMeta.deployment.vmid == "911"
        && pveTestMeta.deployment.proxmox.network == "virtio,bridge=vmbrPxe"
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
