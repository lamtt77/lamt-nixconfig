{ pkgs, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in
pkgs.stdenv.mkDerivation {
  name = "pve-answer-server";
  src = ./.;

  buildInputs = [ pkgs.makeWrapper ];
  nativeCheckInputs = [ pythonEnv ];

  doCheck = true;

  checkPhase = ''
    ${pythonEnv}/bin/python - <<'PY'
    import importlib.util
    import os
    import tempfile

    spec = importlib.util.spec_from_file_location("answer_server", "answer-server.py")
    answer_server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(answer_server)

    with tempfile.TemporaryDirectory() as static_dir:
        nested_asset = os.path.join(static_dir, "proxmox", "linux26")
        assert answer_server.resolve_static_path(
            static_dir, "proxmox/linux26"
        ) == nested_asset

        with tempfile.NamedTemporaryFile() as target:
            symlink_asset = os.path.join(static_dir, "linux26")
            os.symlink(target.name, symlink_asset)
            assert answer_server.resolve_static_path(
                static_dir, "linux26"
            ) == symlink_asset

        assert answer_server.resolve_static_path(static_dir, "../secret") is None
    PY
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp answer-server.py $out/bin/pve-answer-server
    chmod +x $out/bin/pve-answer-server

    wrapProgram $out/bin/pve-answer-server \
      --prefix PATH : "${pythonEnv}/bin"
  '';
}
