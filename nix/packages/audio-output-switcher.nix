{
  flake,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;
in
  flake.lib.writeNushellApplication pkgs {
    name = "audio-output-switcher";
    runtimeInputs = [pkgs.pulseaudio pkgs.wofi];
    meta.platforms = lib.platforms.linux;
    source = ''
      let sinks = (pactl --format=json list sinks | from json)

      let sink_map = ($sinks | each {|x|
        {
          name: $x.name
          desc: ($x.description | str trim)
        }
      } | filter {|x| $x.desc != null })

      let choices = ($sink_map | get desc | str join "\n")
      let selected_desc = (echo $choices | wofi --dmenu --prompt "Select Audio Output" | str trim)

      let selected = ($sink_map | where desc == ($selected_desc | str trim))
      if ($selected | is-empty) == false {
        let selected_name = ($selected | get 0 | get name)
        pactl set-default-sink $selected_name
        for stream in (pactl list short sink-inputs | lines | each { |l| $l | split row "\t" | get 0 }) {
          pactl move-sink-input $stream $selected_name
        }
      }
    '';
  }
