{
  pkgs,
  flake,
  ...
}: {
  imports = [
    flake.homeModules.modern-coreutils-replacements
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.wezterm
    flake.homeModules.zellij
    flake.homeModules.starship
    flake.homeModules.zsh
    flake.homeModules.nushell
    flake.homeModules.nix-index
    flake.homeModules.atuin
    flake.homeModules.llm
    flake.homeModules.nh
  ];

  home = {
    stateVersion = "25.05";
  };

  programs.home-manager.enable = true;

  # Override my default email for commits
  programs.git.userEmail = pkgs.lib.mkForce "gio.damelio@logixboard.com";

  # Setup fonts
  home.packages = [
    # Ubuntu default font
    pkgs.ubuntu_font_family

    # Jetbrains Mono
    pkgs.jetbrains-mono

    # Add Inconsolata Nerdfont
    pkgs.nerd-fonts.inconsolata
    pkgs.nerd-fonts.jetbrains-mono
  ];
}
