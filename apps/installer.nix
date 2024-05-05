# NOTE: this app will only run with Linux platform because of disko

{ inputs, pkgs, ...}:
let
  inherit (inputs) self;
in {
  type = "app";

  # bash script, NOTE: nixos_system build is very resource demanding, slow system may hang!
  # please use staging/remote build for slow system
  program = builtins.toString (pkgs.writeShellScript "installer" ''
    set -e

    if [ "$(id -u)" != "0" ]; then
        echo "The installer must be run as root" 1>&2
        exit 1
    fi

    if [ -z "$1" ]; then
      echo "Usage: installer <hostname>"
      exit 1
    fi
    host=$1

    echo "WARNING: All data of the host '$host' will be destroyed. Confirm (y/N)"
    read -p "Are you sure? " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Aborting"
        exit 1
    fi;

    disko_script=$(
      nix build \
        --print-out-paths \
        --no-link \
        --extra-experimental-features "nix-command flakes" \
        --no-write-lock-file \
        "${self}#nixosConfigurations.\"$host\".config.system.build.diskoScript")

    echo "====>Executing Disko script for format and mount..."
    "$disko_script"

    echo "====>Final installation phase starting..."
    test -f /mnt/root/.ssh/known_hosts || (mkdir -p /mnt/root/.ssh \
      && ssh-keyscan -H tea.lamhub.com > /mnt/root/.ssh/known_hosts)

    # TODO: option to build remotely for low performance system, for now use staging
    nixos_system=$(
      nix build \
        --print-out-paths \
        --no-link \
        --extra-experimental-features "nix-command flakes" \
        --no-write-lock-file \
        "${self}#nixosConfigurations.\"$hostname\".config.system.build.toplevel")

    nixos-install --no-root-password --no-channel-copy --system "$nixos_system"
  '');
}
