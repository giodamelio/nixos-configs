{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "sway-smart-terminal";
  runtimeInputs = with pkgs; [sway wezterm];
  source = ''
    def flatten-sway-tree []: record -> list<record> {
      let node = $in
      let children = (
        ($node.nodes? | default []) | append ($node.floating_nodes? | default [])
      )
      [$node] | append ($children | each { flatten-sway-tree } | flatten)
    }

    def main [] {
      let focused = (swaymsg -t get_tree | from json | flatten-sway-tree | where focused == true | get 0)
      let focused_pane = try { wezterm cli list-clients --format json | from json | get 0 } catch { null }

      let cwd = if ($focused.app_id? == "org.wezfurlong.wezterm" and $focused_pane != null) {
        let pane_id = ($focused_pane.focused_pane_id?)
        if ($pane_id != null) {
          let pane = try {
            wezterm cli list --format json | from json | where pane_id == $pane_id | get 0
          } catch { null }
          if ($pane != null and $pane.cwd? != null) {
            $pane.cwd | url parse | get path
          } else {
            $env.HOME
          }
        } else {
          $env.HOME
        }
      } else {
        $env.HOME
      }

      wezterm start --cwd $cwd
    }
  '';
}
