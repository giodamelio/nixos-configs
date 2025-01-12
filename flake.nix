{
  description = "My personal Nix configs";

  outputs = inputs: inputs.snowfall-lib.mkFlake {
    inherit inputs;

    src = ./.; # Root of the flake

    snowfall = {
      root = ./nix;
      namespace = "giodamelio";
    };

    # Alias the default shell
    alias.shells.default = "development";
  };

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # Unified config loader
    snowfall-lib.url = "github:snowfallorg/lib";
    snowfall-lib.inputs.nixpkgs.follows = "nixpkgs";
  };
}
