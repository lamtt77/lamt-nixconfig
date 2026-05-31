{
  pkgs,
  inputs,
  ...
}: let
  installerPkg = pkgs.rustPlatform.buildRustPackage {
    pname = "installer-rs";
    version = "0.1.0";

    src = inputs.self;
    sourceRoot = "source/apps/installer-rs";

    cargoLock = {
      lockFile = ./installer-rs/Cargo.lock;
    };

    nativeBuildInputs = [pkgs.makeWrapper];

    postInstall = ''
      wrapProgram $out/bin/installer-rs \
        --prefix PATH : ${pkgs.lib.makeBinPath [
        pkgs.git
        pkgs.openssh
        pkgs.nix
        pkgs.jq
        pkgs.rsync
        pkgs.gnumake
        pkgs.coreutils
        pkgs.nmap
        pkgs.hostname
        pkgs.sops
        pkgs.ssh-to-age
      ]}
    '';
  };
in {
  type = "app";
  program = "${installerPkg}/bin/installer-rs";
}
