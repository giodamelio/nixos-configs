{inputs, ...}: {
  den.aspects.nono.homeManager = {
    perSystem,
    pkgs,
    ...
  }: {
    home.packages = [
      # cargoHash is taken from the original args, so vendor the fork ourselves.
      (perSystem.llm-agents.nono.overrideAttrs (final: _: {
        src = inputs.nono;
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit (final) pname version src;
          hash = "sha256-7iEzHYaXA8u8Cj1PDA63cF46uuOePImaJOr4nS1bnZA=";
        };
      }))
    ];
  };
}
