# fonts — system font set. Converted from nix/modules/nixos/fonts.nix.
_: {
  den.aspects.fonts.nixos = {pkgs, ...}: {
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
  };
}
