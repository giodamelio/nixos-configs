{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "reboot-into-entry";
  runtimeInputs = [pkgs.systemd pkgs.wofi];
  source = ''
    # Get the list of boot entries in JSON format
    let entries = (bootctl --json=short list | from json)

    # Filter to only bootable entries and create a map with id and title
    let entry_map = ($entries | each {|x|
      {
        id: $x.id
        title: $x.showTitle
        default: $x.isDefault
      }
    })

    # Create a display string for each entry, marking the default one
    let choices = ($entry_map | each {|x|
      if $x.default {
        $"($x.title) [current default]"
      } else {
        $x.title
      }
    } | str join "\n")

    # Let the user select an entry using wofi
    let selected_title = (echo $choices | wofi --dmenu --prompt "Select Boot Entry" | str trim)

    # Extract just the title without the "[current default]" suffix if present
    let clean_title = if ($selected_title | str contains "[current default]") {
      $selected_title | str replace " [current default]" ""
    } else {
      $selected_title
    }

    # Find the selected entry
    let selected = ($entry_map | where title == $clean_title)

    if ($selected | is-empty) == false {
      let selected_id = ($selected | get 0 | get id)
      print $"Rebooting with boot entry: ($clean_title) [($selected_id)]"
      systemctl reboot --boot-loader-entry=($selected_id)
    } else {
      print "No boot entry selected, aborting."
    }
  '';
}
