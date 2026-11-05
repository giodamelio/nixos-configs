_: {
  # gh only loads extensions from its data dir, not PATH, so they need HM.
  den.aspects.gh.homeManager = {
    perSystem,
    pkgs,
    ...
  }: {
    programs.gh = {
      enable = true;
      extensions = [
        pkgs.gh-stack
        perSystem.self.gh-pin-actions
      ];
    };
  };
}
