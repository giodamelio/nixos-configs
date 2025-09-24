# Instantiates a default Nixpkgs as `pkgs` if it is in $NIX_PATH
_info: _final: _prev: let
  nixpkgs = builtins.tryEval (import <nixpkgs> {});
in
  if nixpkgs.success
  then {
    pkgs = nixpkgs.value;
  }
  else (builtins.trace "No nixpkgs in $NIX_PATH" {})
