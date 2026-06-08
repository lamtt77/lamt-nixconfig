{
  stdenv,
  hugo,
  inputs,
  ...
}:
stdenv.mkDerivation {
  name = "blog";
  src = ../../blog;
  buildInputs = [ hugo ];

  buildPhase = ''
    rm -rf themes
    mkdir -p themes
    cp -r --no-preserve=mode ${inputs.hugo-papermod} themes/hugo-papermod

    hugo --minify
  '';
  installPhase = "cp -r public $out";
}
