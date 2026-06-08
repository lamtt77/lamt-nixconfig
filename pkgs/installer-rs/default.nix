{
  lib,
  rustPlatform,
  makeWrapper,
  git,
  openssh,
  nix,
  jq,
  rsync,
  gnumake,
  coreutils,
  nmap,
  hostname,
  sops,
  ssh-to-age,
  ...
}:
let
  installerSrc = lib.cleanSourceWith {
    src = ../../apps/installer-rs;
    filter =
      path: type:
      let
        name = baseNameOf path;
      in
      !(type == "directory" && (name == "target" || name == ".direnv"))
      && !(type == "symlink" && name == "result");
  };
in
rustPlatform.buildRustPackage {
  pname = "installer-rs";
  version = "0.1.0";

  src = installerSrc;

  cargoLock = {
    lockFile = ../../apps/installer-rs/Cargo.lock;
  };

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mv $out/bin/installer-rs $out/bin/lamd
    ln -s lamd $out/bin/installer-rs

    # big performance improvement with --suffix change, this is to ensure latest nix get loaded
    wrapProgram $out/bin/lamd \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          openssh
          jq
          rsync
          gnumake
          coreutils
          nmap
          hostname
          sops
          ssh-to-age
        ]
      } \
      --suffix PATH : ${lib.makeBinPath [ nix ]}
  '';
}
