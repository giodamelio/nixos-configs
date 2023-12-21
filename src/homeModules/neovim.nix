{
  root,
  debug,
  ...
}: {pkgs, ...}: let
  neovimPackage = root.packages.neovim {inherit pkgs;};
in {
  home.packages = [
    neovimPackage
  ];

  # Set Neovim as the default editor manually.
  # Since we have a custom Neovim package, we can't use the HomeManager module directly
  home.sessionVariables = {EDITOR = "${neovimPackage}/bin/nvim";};
}
