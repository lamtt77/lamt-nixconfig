# NOTE: this app will only run with Linux platform because of disko

{ inputs, pkgs, ...}:
let
  inherit (inputs) self;
  inherit (inputs.self) mydefs;
in {
  type = "app";

  program = builtins.toString (pkgs.writeShellScript "installer-staging" ''
    set -e

    if [ "$(id -u)" != "0" ]; then
        echo "The installer must be run as root" 1>&2
        exit 1
    fi

    FORCE="no"
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) FORCE="yes" ;;
            --) shift; break ;;
            -*) echo "unknown option: $1"; exit 1 ;;
            *) break ;;
        esac
        shift
    done

    if [ -z "$1" ]; then
      echo "Usage: installer --force <hostname>"
      exit 1
    fi
    host=$1

    [ $FORCE == "yes" ] || (
      echo "WARNING: All data of the host '$host' will be destroyed. Confirm (y/N)"
      read -p "Are you sure? " -n 1 -r
      echo
      if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
          echo "Aborting"
          exit 1
      fi;
    )

    disko_script=$(
      nix build \
        --print-out-paths \
        --no-link \
        --extra-experimental-features "nix-command flakes" \
        --no-write-lock-file \
        "${self}#nixosConfigurations.\"$host\".config.system.build.diskoScript")

    echo "Executing Disko script for format and mount..."
    "$disko_script"

    test -f /mnt/root/.ssh/known_hosts || (mkdir -p /mnt/root/.ssh \
      && ssh-keyscan -H tea.lamhub.com > /mnt/root/.ssh/known_hosts)

    nixos-generate-config --force --root /mnt
    cp ${self}/{defines.nix,apps/installer-staging/extra-config.nix} /mnt/etc/nixos
    cp ${self}/modules/os/linux/autorun/zramswap.nix /mnt/etc/nixos
    sed --in-place '/hardware-configuration.nix.*/a\
      \.\/extra-config.nix\n\
    ' /mnt/etc/nixos/configuration.nix

    test -d /mnt/root/${mydefs.myRepoName} && rm -rf /mnt/root/${mydefs.myRepoName}
    cp -r ${self} /mnt/root/${mydefs.myRepoName}
    nixos-install --no-root-password --no-channel-copy
  '');
}
