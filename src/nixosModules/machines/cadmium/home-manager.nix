{
  root,
  inputs,
  homelab,
  ...
}: {
  pkgs,
  config,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  config = {
    users.users.giodamelio = {
      extraGroups = ["wheel" "docker" "sound"];
      isNormalUser = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
    programs.zsh.enable = true;

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.giodamelio = root.homeModules.users.giodamelio-linux;
  };
}
