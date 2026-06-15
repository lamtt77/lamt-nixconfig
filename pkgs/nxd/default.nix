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
  nxdSrc = lib.cleanSourceWith {
    src = ../../apps/nxd;
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
  pname = "nxd";
  version = "0.1.0";

  src = nxdSrc;

  cargoLock = {
    lockFile = ../../apps/nxd/Cargo.lock;
  };

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    git
    rsync
  ];

  postInstall = ''
    wrapProgram $out/bin/nxd \
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

    ln -s nxd $out/bin/lamd
    ln -s nxd $out/bin/installer-rs
  '';
}
