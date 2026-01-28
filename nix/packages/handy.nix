{pkgs, ...}: let
  version = "0.7.0";
  appimage = pkgs.appimageTools.wrapType2 {
    pname = "handy-appimage-unwrapped";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.AppImage";
      hash = "sha256-tTswFYLCPGtMbHAb2bQMsklRiRCVXLrtu4pQC8IHdqQ=";
    };
    extraPkgs = p:
      with p; [
        alsa-lib
      ];
  };
in
  pkgs.writeShellScriptBin "handy" ''
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
    exec ${appimage}/bin/handy-appimage-unwrapped "$@"
  ''
