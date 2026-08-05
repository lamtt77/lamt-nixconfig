_args@{ ... }:
{ ... }:
{
  nxd.operations = {
    identity.includeTags = [ "operation:identity" ];
    # Guest resources are derived from host declarations that also own Nix
    # deployment targets. Keep their exact membership so the PVE operation
    # does not acquire deployment actions.
    pve.resources = [
      "pve-cluster/barcluster"
      "pve-node/barcluster/pve1"
      "pve-node/barcluster/pve2"
      "guest/avon"
      "guest/freenas112R720"
      "guest/gaming"
      "guest/pbs-r720"
      "guest/router-backup"
      "guest/router-main"
      "guest/router-recovery"
      "guest/utils"
      "guest/vyos-1.3-rolling"
      "guest/vyos-124-lambuilt28Mar2020"
    ];
    pve.includeTags = [ "operation:pve" ];
    pve.selectors = [ "pve-host-backup/pve1" ];
    pve-qdevice.resources = [
      "pve-cluster/barcluster"
      "pve-node/barcluster/pve1"
      "pve-node/barcluster/pve2"
    ];
    pbs.includeTags = [ "operation:pbs" ];
    pbs-installer.resources = [ "backup-server/pbs-r720-test" ];
    pbs-installer-cleanup = {
      resources = [ "guest/pbs-r720-test" ];
      lifecycleIntent = "destroy";
    };
    pve-pxe.resources = [ "guest/pve-test" ];
    pve-host-state.selectors = [
      "pve-host-state/pve-test"
      "pve-host-state/pve1"
      "pve-host-state/pve2"
    ];
    vmware.resources = [ "vmware/air15vm" ];
    vmware-test.resources = [ "vmware/air15vm-test" ];
    vmware-test-cleanup = {
      resources = [ "vmware/air15vm-test" ];
      lifecycleIntent = "destroy";
    };
  };
}
