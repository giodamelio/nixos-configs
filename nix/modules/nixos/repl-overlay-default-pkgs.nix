# UNUSED: This repl overlay requires the `repl-overlays` setting which is
# not yet supported in Nix (only Lix). Kept for when Nix gains support.
# REMIND-ME-TO: Re-enable repl-overlays pr_merged=github:NixOS/nix#10203
# REMIND-ME-TO: Re-enable repl-overlays issue_closed=github:NixOS/nix#9940
# REMIND-ME-TO: Re-enable repl-overlays issue_closed=github:NixOS/nix#13264
#
# Instantiates a default Nixpkgs as `pkgs` if it is in $NIX_PATH
_info: _final: _prev: let
  nixpkgs = builtins.tryEval (import <nixpkgs> {});
in
  if nixpkgs.success
  then {
    pkgs = nixpkgs.value;
  }
  else (builtins.trace "No nixpkgs in $NIX_PATH" {})
