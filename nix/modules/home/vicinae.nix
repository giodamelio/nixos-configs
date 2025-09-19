{
  inputs,
  perSystem,
  ...
}: {
  imports = [
    inputs.vicinae.homeManagerModules.default
  ];

  home.packages = [
    perSystem.vicinae.default
  ];

  services.vicinae = {
    enable = true;
    autoStart = true;
  };
}
