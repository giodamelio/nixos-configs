_: {pkgs, ...}:
pkgs.qutebrowser.overrideAttrs (_: prev: {
  # Override source to be from the `tree-tabs-integration` branch
  src = pkgs.fetchFromGitHub {
    owner = "qutebrowser";
    repo = "qutebrowser";
    rev = "tree-tabs-integration";
    hash = "sha256-d4Lyjj78GxdwT8bf1AgGwgzxuhMbbPiZolMWN8/V7cs=";
  };

  # Add some env vars to Qutebrowser to make the rendering clear with Wayland + fractional scaling
  preFixup =
    prev.preFixup
    + ''
      makeWrapperArgs+=(
        --set QT_QPA_PLATFORM wayland
        --set QT_SCALE_FACTOR_ROUNDING_POLICY RoundPreferFloor
      )
    '';
})
