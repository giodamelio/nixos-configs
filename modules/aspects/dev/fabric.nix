_: {
  den.aspects.fabric.homeManager = {perSystem, ...}: {
    home.packages = [perSystem.fabric.default];
  };
}
