{ pkgs, ... }:
{
  homebrew = {
    enable = true; # disable for faster rebuild
    onActivation = {
      upgrade = false; # avoid brew upgrade during routine darwin-rebuild switch
    };

    brews = [
      "llama.cpp"
    ];

    casks = [
      "cleanshot"
      "discord"
      "docker-desktop"
      "dotnet-sdk"
      "firefox"
      "google-chrome"
      "hammerspoon"
      "imageoptim"
      "istat-menus"
      "windows-app"
      "monodraw"
      "oracle-jdk"
      "raycast"
      "rectangle"
      "screenflow"
      "slack"
      "tailscale-app"
      "the-unarchiver"

      # AI stuff
      "claude"
      "cursor"
      "lm-studio"
      "zed"

      # misc
      # "digikam"
      # "iterm2"
      # "spotify"
    ];
  };

  system.activationScripts.postActivation.text = ''
    if ! xcode-select --version 2>/dev/null; then
      xcode-select --install
    fi
    if ! /opt/homebrew/bin/brew --version 2>/dev/null; then
      ${pkgs.bash}/bin/bash -c "$(${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  '';
}
