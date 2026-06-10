{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "check-drv-drift";
  runtimeInputs = [pkgs.jujutsu];
  source = builtins.readFile ./check-drv-drift.nu;
  meta.mainProgram = "check-drv-drift";
}
