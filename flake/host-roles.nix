{
  laptop = {
    tags = [ "client" ];
  };
  workstation = {
    tags = [ "client" ];
  };
  server = {
    server = true;
    tags = [ "server" ];
  };
  router = {
    server = true;
    hasDisko = true;
    tags = [ "infra" ];
  };
  bootstrap = {
    tags = [ "bootstrap" ];
    buildSystem = false;
  };
  wsl = {
    wsl = true;
    tags = [ "wsl" ];
  };
}
