{
  pkgs,
  perSystem,
  ...
}:
pkgs.mkShell {
  buildInputs =
    [
      perSystem.colmena.colmena
      perSystem.ragenix.default

      # config.packages.deploy
      # config.packages.neovim
      # config.packages.agedit

      pkgs.git
      pkgs.nurl
      pkgs.nix-init
      pkgs.nushell
      pkgs.rage
      pkgs.pwgen
      pkgs.dogdns
      pkgs.opentofu
      pkgs.little_boxes
      pkgs.nil
      pkgs.nvd
      pkgs.nix-diff
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      perSystem.morlana.default
    ];
}
