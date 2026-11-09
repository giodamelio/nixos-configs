_: {
  den.aspects.nix-unfree.homeManager = {pkgs, ...}: {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "nix-unfree";
        # --impure is only accepted after the subcommand; this global option is the same switch.
        text = ''
          NIXPKGS_ALLOW_UNFREE=1 exec nix --option pure-eval false "$@"
        '';
      })
    ];
  };
}
