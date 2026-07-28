# Review AI-generated diffs like a GitHub PR from the terminal.
_: {
  den.aspects.tui-review.homeManager = {perSystem, ...}: {
    home.packages = with perSystem.llm-agents; [
      tuicr
      hunk
    ];
  };
}
