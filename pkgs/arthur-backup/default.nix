{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  name = "arthur-backup";
  src = ./.;

  buildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp arthur_universal_backup $out/bin/
    cp universal_backup.conf $out/bin/
    cp rclone-exclude.txt $out/bin/

    wrapProgram $out/bin/arthur_universal_backup \
      --prefix PATH : "${pkgs.rclone}/bin:${pkgs.restic}/bin:${pkgs.borgbackup}/bin:${pkgs.msmtp}/bin"
  '';
}
