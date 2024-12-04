{
  root,
  inputs,
  ...
}: _: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  config = {
    # This is very important to make Nix Darwin and Home Manager work togather
    programs.zsh.enable = true;

    users.users.giodamelio = {
      home = "/Users/giodamelio";
    };
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.giodamelio = root.homeModules.users.giodamelio-darwin;
  };
}
