{
  flake,
  pkgs,
  perSystem,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "sway-smart-terminal";
  runtimeInputs = [perSystem.giopkgs.wezterm];
  source = ''
    def main [] {
      let cwd = if ("/tmp/wezterm-cwd" | path exists) {
        open /tmp/wezterm-cwd | str trim
      } else {
        $env.HOME
      }

      wezterm start --cwd $cwd
    }
  '';
}
