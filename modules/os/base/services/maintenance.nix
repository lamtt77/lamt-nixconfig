{
  pkgs,
  lib,
  config,
  options,
  ...
}:
with lib;
{
  config = mkMerge [
    # --- Linux/NixOS Maintenance ---
    (mkIf pkgs.stdenv.isLinux (
      {
        # Automatic Garbage Collection
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };

        # Optimize storage (hard-link duplicates)
        nix.settings.auto-optimise-store = true;
      }
      // optionalAttrs (options.services ? fstrim) {
        # Trim SSDs (crucial for VPS/Cloud/VMs)
        services.fstrim.enable = true;
      }
      // optionalAttrs (options ? boot) {
        # Keep bootloader clean
        boot.loader.grub.configurationLimit = mkDefault 10;
        boot.loader.systemd-boot.configurationLimit = mkForce 10;
      }
    ))

    # --- Darwin/macOS Maintenance ---
    (mkIf pkgs.stdenv.isDarwin (
      {
        # Disable auto-optimise-store at build-time to avoid daemon corruption on macOS
        nix.settings.auto-optimise-store = false;
      }
      // optionalAttrs (options ? launchd) {
        # Custom launchd daemons for Nix GC and Store Optimization.
        # We define these manually because nix-darwin's built-in nix.gc.automatic
        # and nix.optimise.automatic assertions require nix.enable = true.
        launchd.daemons.custom-nix-gc = {
          command = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 14d";
          serviceConfig = {
            RunAtLoad = false;
            StartCalendarInterval = [
              {
                Weekday = 7;
                Hour = 3;
                Minute = 15;
              }
            ]; # Weekly on Sunday at 3:15 AM
            StandardOutPath = "/var/log/nix-gc.log";
            StandardErrorPath = "/var/log/nix-gc.err";
            LowPriorityIO = true;
            ProcessType = "Background";
            Nice = 20;
          };
        };

        launchd.daemons.custom-nix-optimise = {
          command = "${pkgs.nix}/bin/nix-store --optimise";
          serviceConfig = {
            RunAtLoad = false;
            StartCalendarInterval = [
              {
                Weekday = 7;
                Hour = 4;
                Minute = 15;
              }
            ]; # Weekly on Sunday at 4:15 AM
            StandardOutPath = "/var/log/nix-optimise.log";
            StandardErrorPath = "/var/log/nix-optimise.err";
            LowPriorityIO = true;
            ProcessType = "Background";
            Nice = 20;
          };
        };
      }
    ))
  ];
}
