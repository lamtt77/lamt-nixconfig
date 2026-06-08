{
  class = "nixos";
  system = "x86_64-linux";
  username = "lamt";
  wsl = true;
  hasDisko = false;

  cross = {
    localSystem = "aarch64-linux";
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };
}
