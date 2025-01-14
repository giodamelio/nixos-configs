{pkgs, ...}:
pkgs.mkShell {
  packages = with pkgs; [
    nil # Nix Language Server
    nushell # Powerfull Rust based shell
    little_boxes # Pretty boxes in your shell
    rage # Rust reimplementation of Age encryption

    # Easily create new packages
    nurl
    nix-init
  ];
}
