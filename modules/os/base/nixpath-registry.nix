{
  inputs,
  config,
  lib,
  mydefs,
  ...
}:
{
  # when turn on everything (i.e nix-env) will be locked in flake.lock
  environment.etc.nixpkgs.source = inputs.nixpkgs;
  nix = {
    nixPath = [ "nixpkgs=/etc/${config.environment.etc.nixpkgs.target}" ];
    registry = {
      nixpkgs.flake = inputs.nixpkgs;

      github.to = {
        type = "github";
        owner = mydefs.githubUser;
        repo = mydefs.myRepoName;
      };

      tea.to = {
        type = "git";
        url = "ssh://git@${mydefs.teaURL}/${mydefs.githubUser}/${mydefs.myRepoName}";
      };
    };
  };
}
