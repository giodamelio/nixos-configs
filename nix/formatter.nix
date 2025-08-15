{
  pkgs,
  flake,
  ...
}: let
  treefmt = flake.lib.treefmt pkgs;
in
  treefmt.wrapper
