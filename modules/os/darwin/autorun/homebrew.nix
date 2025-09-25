{
  pkgs,
  ...
}: {
  homebrew = {
    enable = true; # disable for faster rebuild
    onActivation = {
      cleanup = "zap"; # uninstalls all formulae not listed in brewfile
      upgrade = true; # run 'brew upgrade' on activation
    };

    brews = [
      "codex"
      "gemini-cli"
      "llama.cpp"
      "sst/tap/opencode"
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
      "microsoft-remote-desktop"
      "monodraw"
      "oracle-jdk"
      "raycast"
      "rectangle"
      "screenflow"
      "slack"
      "the-unarchiver"

      # AI stuff
      "claude"
      "claude-code"
      "cursor"
      "lm-studio"
      "zed"

      # misc
      # "digikam"
      # "iterm2"
      # "spotify"
    ];
    # taps = [
    #   "homebrew/cask"
    # ];
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
