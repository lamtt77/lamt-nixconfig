# Optional operator install of the NXD CLI into Home Manager.
#
# Prefer local development via the nxd worktree:
#   just build   # in ~/lab/nxd
#   export NXD=$HOME/lab/nxd/target/debug/nxd
#
# Do not enable this on profiles where a dirty path: nxd input would rebuild
# pkgs.nxd on every switch. System services that need nxd (e.g. pve-pxe bootstrap)
# should depend on pkgs.nxd in the OS module, not this HM feature.
{ pkgs, ... }:
{
  home.packages = [ pkgs.nxd ];
}
