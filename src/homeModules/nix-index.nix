_: {pkgs, ...}: {
  home.packages = with pkgs; [
    nix-index
    comma
  ];
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };
}
