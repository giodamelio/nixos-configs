{
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
}
