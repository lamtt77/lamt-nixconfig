/* This contains various packages we want to overlay, manually. Note that the
 * other ".nix" files in /pkgs/ directory are automatically loaded.
 */
final: prev: {
  create-dmg = final.callPackage ../pkgs/_manual/create-dmg.nix {};

  # Fix 1password not working properly on Linux arm64.
  _1password = final.callPackage ../pkgs/_manual/1password.nix {};
}
