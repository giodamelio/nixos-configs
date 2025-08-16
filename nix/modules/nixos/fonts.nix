{pkgs, ...}: {
  fonts = {
    packages = with pkgs;
    with pkgs.nerd-fonts; [
      ubuntu-sans
      inconsolata
      jetbrains-mono
      symbols-only
      pkgs.noto-fonts
    ];
  };
}
