{
  inputs,
  pkgs,
  ...
}: let
  evaledModule = inputs.treefmt-nix.lib.evalModule pkgs (import ../treefmt.nix);
  treefmt = evaledModule.config.build;
in
  treefmt.wrapper
