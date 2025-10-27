{pkgs, ...}: let
  inherit (pkgs) lib;

  # There is a conflict in feature names between nix and lix
  # DANGER: The implementations aren't actually the same
  # they have different precedence. As long as I don't mix both
  # pipes in the same expression we should be safe though
  # See: https://discourse.nixos.org/t/lix-mismatch-in-feature-name-compared-to-nix/59879
  experimentalFeaturesToRemove = ["pipe-operators"];
in {
  config = {
    # This might not actually be taking effect
    nixpkgs.overlays = [
      (_final: prev: {
        inherit
          (prev.lixPackageSets.latest)
          nixpkgs-review
          nix-eval-jobs
          nix-fast-build
          colmena
          ;
      })
    ];

    nix = {
      package = pkgs.lixPackageSets.stable.lix;
      settings = {
        extra-experimental-features = [
          "pipe-operator"
          "fetch-closure"
        ];

        # Add some helpers to `nix repl` via `repl-overlays`
        # https://docs.lix.systems/manual/lix/stable/command-ref/conf-file.html#conf-repl-overlays
        repl-overlays = [
          ./repl-overlay-default-pkgs.nix
          ./repl-overlay-collapse-system.nix
        ];
      };
    };
  };

  # Override apply function to allow removing existing features
  options.nix.settings = {
    extra-experimental-features = lib.mkOption {
      apply = featList: lib.filter (feat: !builtins.elem feat experimentalFeaturesToRemove) featList;
    };
  };
}
