# Lets Chrome's WebHID/WebUSB reach the Fractal Scape dongle at adjust.fractal-design.com.
_: {
  den.aspects.cadmium-fractal-headset.nixos = {pkgs, ...}: let
    headsetNode = "alsa_input.usb-Fractal_Fractal_Scape_Dongle_00000000911AD4AV1317-00.mono-fallback";
    webcamNode = "alsa_input.usb-046d_HD_Pro_Webcam_C920_EA22F16F-02.analog-stereo";
    smart-mic = pkgs.buildGoModule {
      pname = "smart-mic";
      version = "0.1.0";
      src = ./smart-mic;
      vendorHash = null;
    };
  in {
    users.groups.fractal = {};
    users.users.giodamelio.extraGroups = ["fractal"];

    # Vendor-only match: the dongle may re-enumerate with a different product ID while flashing.
    services.udev.extraRules = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="36bc", MODE="0660", GROUP="fractal"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="36bc", MODE="0660", GROUP="fractal"
    '';

    # "Smart Mic": a stable source fed by one real mic at a time. The smart-mic
    # service retargets smart-mic-capture; mute/volume on smart-mic apply after
    # the switch, so a software mute holds regardless of which mic feeds it.
    services.pipewire.extraConfig.pipewire."90-smart-mic" = {
      "context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Smart Mic";
            "capture.props" = {
              "node.name" = "smart-mic-capture";
              "audio.position" = ["MONO"];
              "target.object" = headsetNode;
              # Only pulls from the real mic while something records from smart-mic.
              "node.passive" = true;
            };
            "playback.props" = {
              "node.name" = "smart-mic";
              "node.description" = "Smart Mic";
              "media.class" = "Audio/Source";
              "audio.position" = ["MONO"];
              # Above any real device (ALSA tops out around 2000), so WirePlumber picks it as the default source.
              "priority.session" = 3000;
            };
          };
        }
      ];
    };

    systemd.user.services.smart-mic = {
      description = "Switch Smart Mic between headset and webcam by boom position";
      wantedBy = ["pipewire.service"];
      after = ["pipewire.service" "wireplumber.service"];
      path = [pkgs.pipewire];
      serviceConfig = {
        # This dongle's patched firmware pushes boom/mute, so the poll is only a slow fallback.
        ExecStart = "${smart-mic}/bin/smart-mic -headset ${headsetNode} -webcam ${webcamNode} -poll 1s";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
