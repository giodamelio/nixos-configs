{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "files_that_change_togather";
  runtimeInputs = [pkgs.git];
  source = builtins.readFile ./files_that_change_togather.nu;
}
