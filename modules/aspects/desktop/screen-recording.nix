_: {
  den.aspects.screen-recording.homeManager = {perSystem, ...}: {
    home.packages = [
      perSystem.giopkgs.cap-desktop
    ];
  };
}
