_: {
  pkgs,
  lib,
  ...
}: let
  # Add some env vars to Qutebrowser to make the rendering clear with Wayland + fractional scaling
  wrappedQutebrowser = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (pkgs.qutebrowser.overrideAttrs (_: prev: {
    preFixup =
      prev.preFixup
      + ''
        makeWrapperArgs+=(
          --set QT_QPA_PLATFORM wayland
          --set QT_SCALE_FACTOR_ROUNDING_POLICY RoundPreferFloor
        )
      '';
  }));
in {
  programs.qutebrowser = {
    enable = true;
    package = wrappedQutebrowser;
  };
}
