# llm-tooling — grab bag of LLM CLIs that don't warrant their own aspect.
_: {
  den.aspects.llm-tooling.homeManager = {perSystem, ...}: {
    home.packages = [
      perSystem.fabric.default
    ];
  };
}
