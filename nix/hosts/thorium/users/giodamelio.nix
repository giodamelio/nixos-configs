{
  pkgs,
  flake,
  ...
}: {
  imports = [
    flake.homeModules.required
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
    flake.homeModules.claude-code
  ];

  home = {
    stateVersion = "25.05";
  };

  programs.home-manager.enable = true;

  # Configure nix-activate-config for Darwin
  gio.nix-activate-config.activation = {system = "darwin";};

  # Override my default email for commits
  programs.git.userEmail = pkgs.lib.mkForce "gio.damelio@logixboard.com";

  # Setup fonts
  home.packages = with pkgs;
  with pkgs.nerd-fonts; [
    ubuntu-sans
    inconsolata
    jetbrains-mono
  ];

  # Configure Claude Code
  programs.claude-code = {
    enable = true;
    agents = {
      postgres-db-expert = ../../../modules/home/claude-code/agents/postgres-db-expert.md;
    };
    commands = {
      plan-save = ../../../modules/home/claude-code/commands/plan-save.md;
      plan-load = ../../../modules/home/claude-code/commands/plan-load.md;
      pre-commit = {
        markdown = ../../../modules/home/claude-code/commands/pre-commit.md;
        script = ../../../modules/home/claude-code/commands/pre-commit.sh;
      };
    };
  };
}
