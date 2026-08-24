# llm-tooling — grab bag of LLM CLIs that don't warrant their own aspect.
_: {
  den.aspects.llm-tooling.homeManager = {
    perSystem,
    pkgs,
    ...
  }: {
    home.packages = [
      perSystem.fabric.default

      # Vikunja CLI for agents; passthru of pkgs.vikunja, so it stays version-locked
      # to whatever gallium runs.
      pkgs.vikunja.veans
    ];
  };
}
