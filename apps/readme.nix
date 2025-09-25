{pkgs, ...}: {
  type = "app";

  program = "${pkgs.writeShellScript "readme" ''
    ${pkgs.glow}/bin/glow --pager ${../README.md}
  ''}";

  meta = {
    description = "Display the project README with glow";
  };
}
