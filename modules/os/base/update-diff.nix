{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux isDarwin;

  # The path to the current generation
  currentSystem = if isDarwin then "/nix/var/nix/profiles/system" else "/run/current-system";

  # The script content
  diffScript = ''
    if [ -e "${currentSystem}" ]; then
      OLD_SYSTEM=$(${pkgs.coreutils}/bin/readlink -f "${currentSystem}")

      if [ -n "$systemConfig" ]; then
        TARGET_SYSTEM="$systemConfig"
      else
        # Fallback for Darwin
        # In nix-darwin, the activation script is located in the system's store path
        TARGET_SYSTEM=$(dirname "$0")
        TARGET_SYSTEM=$(${pkgs.coreutils}/bin/readlink -f "$TARGET_SYSTEM")
      fi

      if [ -n "$TARGET_SYSTEM" ]; then
        echo "#############################        diff to current-system        ##############################"
        # echo "DEBUG: Old: $OLD_SYSTEM"
        # echo "DEBUG: New: $TARGET_SYSTEM"
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${
          if config.nix.enable then "${config.nix.package}/bin" else "/nix/var/nix/profiles/default/bin"
        } diff "$OLD_SYSTEM" "$TARGET_SYSTEM" || true
        echo "#############################      end diff to current-system      ##############################"
      fi
    fi
  '';
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.nvd ];
    }
    (lib.mkIf isLinux {
      system.activationScripts.diff = {
        supportsDryActivation = true;
        text = diffScript;
      };
    })

    (lib.mkIf isDarwin {
      # Darwin activation scripts structure
      system.activationScripts.postActivation.text = diffScript;
    })
  ];
}
