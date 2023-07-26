{
  description = "";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixos-generators.url = "flake:nixos-generators";
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
      nixosModules = {
        beryllium = import ./nixosModules/beryllium.nix flakeContext;
      };
      packages = {
        x86_64-linux = {
          beryllium-do = import ./packages/beryllium-do.nix flakeContext;
          beryllium-hyperv = import ./packages/beryllium-hyperv.nix flakeContext;
        };
      };
    };
}
