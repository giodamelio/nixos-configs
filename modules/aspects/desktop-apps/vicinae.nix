# vicinae — Raycast-style launcher with extensions. Converted from
# nix/modules/home/vicinae.nix.
_: {
  den.aspects.vicinae.homeManager = {
    pkgs,
    perSystem,
    ...
  }: {
    home.packages = [
      pkgs.vicinae
    ];

    # TODO: When started with SystemD, Vicinae files to launch many programs
    # Instead we will launch it with a sway startup command
    programs.vicinae = {
      enable = true;
      systemd = {
        enable = false;
        autoStart = false;
      };
      extensions = with perSystem.vicinae-extensions; [
        nix
        # systemd # Not in the flake for some reason right now
        it-tools
        firefox
      ];
    };
  };
}
