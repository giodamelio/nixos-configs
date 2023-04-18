{
  description = "My NixOS Systems";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
  };

  inputs = {
    # Follow the unstable nixpkgs by default
    nixpkgs.url = "nixpkgs/nixos-unstable";

    # std keeps things organized
    std = {
      url = "github:divnix/std";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    # Hive builds on std but with more NixOS
    hive = {
      url = "github:divnix/hive";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        colmena.follows = "colmena";
      };
    };

    # Allows easy deploying of our configs
    colmena = {
      url = "github:zhaofengli/colmena";
    };
  };

  outputs = {
    self,
    hive,
    std,
    ...
  } @ inputs: hive.growOn {
    inherit inputs;

    cellsFrom = ./nix;
    cellBlocks = with std.blockTypes; with hive.blockTypes; [
      (devshells "devshells")
    ];
  } {
    devShells = std.harvest self ["giodamelio" "devshells"];
  } {
    # Hive stuff?
  };
}
