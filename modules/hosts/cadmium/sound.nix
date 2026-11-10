{den, ...}: {
  den.aspects.cadmium-sound = {
    includes = [
      den.aspects.cadmium-fractal-headset
    ];

    nixos = {
      pkgs,
      lib,
      ...
    }: let
      # Extra Keywords make apps findable in Noctalia; symlinkJoin avoids rebuilding the app.
      withKeywords = pkg: desktopFile: keywords:
        pkgs.symlinkJoin {
          name = "${pkg.pname}-searchable";
          paths = [pkg];
          postBuild = ''
            desktop=share/applications/${desktopFile}
            grep -q '^Keywords=' ${pkg}/$desktop || {
              echo "withKeywords: no Keywords= line in ${pkg}/$desktop" >&2
              exit 1
            }
            rm $out/$desktop
            sed '/^Keywords=/s/;*$/;${lib.concatStringsSep ";" keywords};/' \
              ${pkg}/$desktop > $out/$desktop
          '';
        };
    in {
      environment.systemPackages = [
        (withKeywords pkgs.qpwgraph "org.rncbc.qpwgraph.desktop" [
          "Patchbay"
          "Patch"
          "Graph"
          "Sound"
          "Audio"
          "Mixer"
          "Routing"
          "Connections"
        ])
        (withKeywords pkgs.easyeffects "com.github.wwmm.easyeffects.desktop" [
          "Mic"
          "Microphone"
          "Sound"
          "Audio"
          "EQ"
          "Effects"
          "Noise"
          "Noise Suppression"
          "Denoise"
          "Gate"
          "Voice"
          "PipeWire"
          "Bass"
          "Headphones"
          "Speakers"
        ])
        (withKeywords pkgs.pwvucontrol "com.saivert.pwvucontrol.desktop" [
          "Volume"
          "Mixer"
          "Audio"
          "Sound"
          "PipeWire"
          "Streams"
          "Applications"
          "Per-App"
          "Levels"
          "Sink"
          "Source"
          "Playback"
          "Recording"
        ])
      ];
    };
  };
}
