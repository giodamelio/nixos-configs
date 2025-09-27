{flake, ...}: {
  imports = [
    flake.homeModules.required
    flake.homeModules.modern-coreutils-replacements
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.zellij
    flake.homeModules.starship
    flake.homeModules.zsh
    flake.homeModules.nushell
    flake.homeModules.nix-index
    flake.homeModules.atuind
    flake.homeModules.llm
    flake.homeModules.claude-code
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.11";
  };

  programs.home-manager.enable = true;

  # Configure Claude Code
  programs.claude-code = {
    enable = true;
    agents = {};
    commands = {
      plan-save = ../../../modules/home/claude-code/commands/plan-save.md;
      plan-load = ../../../modules/home/claude-code/commands/plan-load.md;
      pre-commit = {
        markdown = ../../../modules/home/claude-code/commands/pre-commit.md;
        script = ../../../modules/home/claude-code/commands/pre-commit.sh;
      };
    };
  };

  # Configure nix-activate for NixOS-WSL
  gio.nix-activate-config.activation = {system = "nixos";};
}
