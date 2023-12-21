{
  root,
  inputs,
  ...
}:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  modules = [
    root.homeModules.user-giodamelio
    root.homeModules.modern-coreutils
    root.homeModules.git
    root.homeModules.neovim
  ];
}
