# tuicr — review AI-generated diffs like a GitHub PR from the terminal.
_: {
  den.aspects.tuicr.homeManager = {perSystem, ...}: {
    home.packages = [
      perSystem.llm-agents.tuicr
    ];
  };
}
