{
  lib,
  ...
}:
{
  imports = [
    ../medo
  ];

  networking.hostName = lib.mkForce "medo-test";
  networking.useDHCP = lib.mkForce true;

  services.qemuGuest.enable = true;

  # corosync-qnetd on `medo` is a deliberate prerequisite for the barcluster
  # QDevice witness (LAMT-09). medo-test is not a qnet witness and must not
  # have the unit pulled into the boot transaction.
  systemd.services.corosync-qnetd.wantedBy = lib.mkForce [ ];

}
