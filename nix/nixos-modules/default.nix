_: {
  imports = [
    ./monitoring.nix
  ];

  nixpkgs.overlays = [
    (import ../overlays/wezterm.nix)
  ];
}
