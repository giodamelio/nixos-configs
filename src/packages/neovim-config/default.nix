{
  self,
  pkgs,
  debug,
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "neovim-config";
  src = ./src;

  buildInputs = with pkgs; [vimPlugins.lazy-nvim];
  lazyvim = pkgs.vimPlugins.lazy-nvim;

  installPhase = ''
    mkdir $out
    substituteAllInPlace init.lua
    install -D -t $out *
  '';
}
