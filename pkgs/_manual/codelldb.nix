{
  stdenv,
  fetchurl,
  unzip,
  lib,
  lldb,
}:
stdenv.mkDerivation rec {
  pname = "codelldb";
  version = "1.11.5";

  # Dynamic URL and hash selection based on platform
  src =
    let
      baseUrl = "https://github.com/vadimcn/codelldb/releases/download/v${version}";
      platformData = {
        "aarch64-darwin" = {
          url = "${baseUrl}/codelldb-darwin-arm64.vsix";
          sha256 = "1zfp1sg5za0pcqbfs54c0q9685p6d9gkmaz56rf7vignid7dmdjd";
        };
        "x86_64-darwin" = {
          url = "${baseUrl}/codelldb-darwin-x64.vsix";
          sha256 = "0cnfmfksqslqgwxw7i29rqq5zkhkdksim26db7q7aynv4dbyxwb6";
        };
        "x86_64-linux" = {
          url = "${baseUrl}/codelldb-linux-x64.vsix";
          sha256 = "0y09q8ssyrayyaxpvmsdip25lccg543gw8haf3jq0yxlh2pky88p";
        };
        "aarch64-linux" = {
          url = "${baseUrl}/codelldb-linux-arm64.vsix";
          sha256 = "1i3gvhpal0cpjwfpl6sr025190ly16b7g6xanjw4x09nr4a50s1q";
        };
      };
      platform = stdenv.hostPlatform.system;
      data = platformData.${platform} or (throw "Unsupported platform: ${platform}");
    in
    fetchurl {
      inherit (data) url;
      inherit (data) sha256;
    };

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    unzip $src
  '';

  installPhase =
    let
      libExt = if stdenv.hostPlatform.isDarwin then "dylib" else "so";
    in
    ''
          mkdir -p $out/bin $out/share/codelldb

          # Copy the binary
          cp extension/adapter/codelldb $out/bin/codelldb-unwrapped
          chmod +x $out/bin/codelldb-unwrapped

          # Copy all extension files
          cp -r extension/* $out/share/codelldb/ 2>/dev/null || true

          # Create symlink for scripts in expected location
          mkdir -p $out/bin/scripts
          ln -s $out/share/codelldb/adapter/scripts/* $out/bin/scripts/

          # Create a wrapper that uses LLDB library from the lldb package
          cat > $out/bin/codelldb << EOF
      #!/bin/bash
      # Set PYTHONPATH to include codelldb scripts
      export PYTHONPATH="$out/share/codelldb/adapter/scripts:\$PYTHONPATH"
      # Run codelldb with the correct library path from lldb package
      exec "$out/bin/codelldb-unwrapped" --liblldb "${lldb}/lib/liblldb.${libExt}" "\$@"
      EOF
          chmod +x $out/bin/codelldb
    '';

  meta = with lib; {
    description = "A native debugger extension for VSCode based on LLDB";
    homepage = "https://github.com/vadimcn/codelldb";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
  };
}
