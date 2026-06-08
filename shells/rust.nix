{ pkgs, ... }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    cargo
    clippy
    rustc
    rustfmt
    rust-analyzer
  ];

  RUST_BACKTRACE = 1;
}
