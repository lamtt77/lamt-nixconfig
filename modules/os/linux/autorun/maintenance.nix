{
  pkgs,
  lib,
  ...
}:
with lib; {
  config = mkIf pkgs.stdenv.isLinux {
    # --- Standard Linux Maintenance ---

    # Automatic Garbage Collection
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    # Optimize storage (hard-link duplicates)
    nix.settings.auto-optimise-store = true;

    # Trim SSDs (crucial for VPS/Cloud/VMs)
    services.fstrim.enable = true;

    # Keep bootloader clean
    # boot.nix sets systemd-boot to 15, we override/ensure 10 here
    boot.loader.grub.configurationLimit = mkDefault 10;
    boot.loader.systemd-boot.configurationLimit = mkForce 10;
  };
}
