_: {
  nixpkgs.overlays = [
    (import ../overlays/wezterm.nix)
  ];
}

