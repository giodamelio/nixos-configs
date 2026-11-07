_: {
  den.aspects.call-recording.homeManager = {perSystem, ...}: {
    home.packages = [
      perSystem.giopkgs.anarlog
    ];
  };
}
