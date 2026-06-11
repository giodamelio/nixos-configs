# neovim — my custom wrapped Neovim as the default editor. Converted from
# nix/modules/home/neovim.nix; `perSystem` is a module arg from the per-system
# aspect.
_: {
  den.aspects.neovim.homeManager = {
    perSystem,
    pkgs,
    ...
  }: let
    inherit (pkgs) lib;
    customNeovim = perSystem.neovim-configs.default;
  in {
    home.packages =
      [
        customNeovim
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.wl-clipboard
      ];

    # Set Neovim as the default editor manually.
    # Since we have a custom Neovim package, we can't use the HomeManager module directly
    home.sessionVariables = {EDITOR = "${customNeovim}/bin/nvim";};

    programs.neovim = {
      package = customNeovim;
      vimAlias = true;
    };
  };
}
