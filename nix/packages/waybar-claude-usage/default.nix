{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "waybar-claude-usage";
  source = builtins.readFile ./waybar-claude-usage.nu;
}
