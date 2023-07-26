{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixos-generators.url = "flake:nixos-generators";
    testing.url = "git+https://git.mynixos.com/giodamelio/testing.git";
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };
    in
    {
      nixosConfigurations = {
        beryllium = import ./nixosConfigurations/beryllium.nix flakeContext;
      };
      packages = {
        x86_64-linux = {
          beryllium = import ./packages/beryllium.nix flakeContext;
        };
      };
    };
}
