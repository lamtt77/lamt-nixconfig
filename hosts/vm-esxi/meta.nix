{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  hasDisko = true;

  cross = {
    localSystem = "aarch64-linux";
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };
}
