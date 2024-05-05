{
  homebrew = {
    enable = true;              # disable for faster rebuild
    onActivation = {
      autoUpdate = false;
      # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
      cleanup = "zap";
    };

    casks = [
      "cleanshot"
      "discord"
      "google-chrome"
      "firefox"
      "hammerspoon"
      "imageoptim"
      "istat-menus"
      "monodraw"
      "raycast"
      "rectangle"
      "screenflow"
      "slack"
      # "spotify"
      # "iterm2"
      # "digikam"
    ];
    # taps = [
    #   "homebrew/cask"
    # ];
  };
}
