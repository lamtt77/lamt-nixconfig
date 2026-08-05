{ pkgs, ... }:

pkgs.st.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    ./patches/st-scrollback-0.9.2.diff
    ./patches/st-scrollback-mouse-0.9.2.diff
    ./patches/st-scrollback-mouse-altscreen-20220127-2c5edf2.diff
    ./patches/st-clipboard-0.8.3.diff
    ./patches/st-gruvbox-dark-0.9.3.diff
  ];

  # Expand scrollback buffer to 100,000 lines (scrollback patch default is 2,000)
  postPatch = (oldAttrs.postPatch or "") + ''
    substituteInPlace st.c \
      --replace-fail "#define HISTSIZE      2000" "#define HISTSIZE      100000"
  '';
})
