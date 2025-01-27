{inputs, ...}: {pkgs, ...}: let
  neovimPackage = inputs.self.packages.${pkgs.stdenv.system}.neovim;
in {
  home.packages = [
    neovimPackage
    pkgs.wl-clipboard
  ];

  # Set Neovim as the default editor manually.
  # Since we have a custom Neovim package, we can't use the HomeManager module directly
  home.sessionVariables = {EDITOR = "${neovimPackage}/bin/nvim";};
}
