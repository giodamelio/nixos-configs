_: {
  den.aspects.veans.homeManager = {pkgs, ...}: {
    # Vikunja CLI for agents; passthru of pkgs.vikunja, so it stays version-locked
    # to whatever gallium runs.
    home.packages = [pkgs.vikunja.veans];
  };
}
