{ pkgs, lib, ... }:
# Pure template substitution helper using Python to robustly handle multiline and special chars
{
  name,
  template,
  replacements,
}:
let
  replaceScript = pkgs.writeScript "replace-script.py" ''
    import sys
    import json

    template_path = sys.argv[1]
    replacements_path = sys.argv[2]
    output_path = sys.argv[3]

    with open(template_path, 'r') as f:
        content = f.read()

    with open(replacements_path, 'r') as f:
        replacements = json.load(f)

    for placeholder, value in replacements.items():
        content = content.replace(placeholder, str(value))

    with open(output_path, 'w') as f:
        f.write(content)
  '';
  replacementsJson = pkgs.writeText "replacements-${name}.json" (builtins.toJSON replacements);
in
pkgs.runCommand name { } ''
  ${pkgs.python3}/bin/python ${replaceScript} ${template} ${replacementsJson} $out
''
