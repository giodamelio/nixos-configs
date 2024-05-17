{inputs, ...}: {
  pkgs,
  inputs',
  system,
  ...
}: let
  # Update the Neovim Version
  neovim_010_overlay = _: super: {
    neovim-unwrapped = super.neovim-unwrapped.overrideAttrs (_: rec {
      version = "0.10.0";

      src = pkgs.fetchFromGitHub {
        owner = "neovim";
        repo = "neovim";
        rev = "v${version}";
        hash = "sha256-FCOipXHkAbkuFw9JjEpOIJ8BkyMkjkI0Dp+SzZ4yZlw=";
      };
    });
  };

  # Copy of Nixpkgs with Neovim version overridden
  pkgsWithOverlay = import inputs.nixpkgs {
    inherit system;
    overlays = [neovim_010_overlay];
  };
in
  inputs'.nixvim.legacyPackages.makeNixvim {
    # Use our updated version of Neovim 0.10.0
    package = pkgsWithOverlay.neovim-unwrapped;

    colorschemes.tokyonight.enable = true;
  }
