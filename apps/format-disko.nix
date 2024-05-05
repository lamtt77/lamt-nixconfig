{ inputs, pkgs, ...}:
let
  inherit (inputs) self;
in {
  type = "app";

  # bash script
  program = builtins.toString (pkgs.writeShellScript "format-disko" ''
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
  '');
}
