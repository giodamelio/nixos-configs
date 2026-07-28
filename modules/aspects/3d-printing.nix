_: {
  den.aspects."3d-printing".nixos = {
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    # nixpkgs' orca-slicer ships unwrapped — its wrapGAppsHook3 never produces a
    # wrapper, so the binary runs with no GSettings schemas (the file picker
    # aborts), no GStreamer plugin path (no H.264 decoder, no gtksink for the
    # printer liveview) and none of the WebKit env its preFixup intends. Re-run
    # the hook over a symlink to the real binary to get all of that back.
    #
    # GDK_BACKEND: wxWidgets miscomputes dialog layout on Wayland at output
    # scale 2, so settings windows render shrunk into a corner. XWayland is the
    # only thing that fixes it; set-default so it can still be overridden.
    orca-slicer = pkgs.stdenv.mkDerivation {
      inherit (pkgs.orca-slicer) pname version meta;

      dontUnpack = true;

      nativeBuildInputs = [pkgs.wrapGAppsHook3];
      buildInputs = with pkgs; [
        glib
        glib-networking
        gsettings-desktop-schemas
      ];

      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        ln -s ${pkgs.orca-slicer}/bin/orca-slicer $out/bin/orca-slicer
        ln -s ${pkgs.orca-slicer}/share $out/share

        runHook postInstall
      '';

      preFixup = ''
        gappsWrapperArgs+=(
          --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPathOutput "out" "lib/gstreamer-1.0" (with pkgs.gst_all_1; [
          gstreamer
          gst-plugins-base
          # gtksink: the element orca-slicer looks for on Wayland
          (gst-plugins-good.override {gtkSupport = true;})
          gst-plugins-bad
          gst-libav
        ])}"
          --set WEBKIT_DISABLE_COMPOSITING_MODE 1
          --set-default GDK_BACKEND x11
        )
      '';
    };
  in {
    environment.systemPackages = [
      pkgs.openscad-unstable
      orca-slicer
      perSystem.giopkgs.bambu-studio
    ];
  };
}
