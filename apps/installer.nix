{ pkgs, inputs, ... }:
let
  installerPkg = pkgs.stdenv.mkDerivation {
    name = "lamt-installer";

    src = inputs.self;

    buildInputs = [ pkgs.bash ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    # We don't want to build the project using the Makefile found in src
    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
      mkdir -p $out/src
      # Copy source
      cp -r . $out/src

      mkdir -p $out/bin

      # Ensure installer script is executable
      chmod +x $out/src/apps/installer2/bin/installer

      # Create the executable wrapper
      makeWrapper $out/src/apps/installer2/bin/installer $out/bin/installer \
        --prefix PATH : ${pkgs.lib.makeBinPath [
          pkgs.git
          pkgs.openssh
          pkgs.nix
          pkgs.jq
          pkgs.rsync
          pkgs.gnumake
          pkgs.coreutils
          pkgs.nmap
          pkgs.hostname # Needed for defaults in Makefile/Orchestrator
        ]}
    '';
  };
in
{
  type = "app";
  program = "${installerPkg}/bin/installer";
}

