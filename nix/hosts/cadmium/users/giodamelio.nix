{
  flake,
  perSystem,
  ...
}: let
  inherit (flake.lib.homelab.machines.cadmium) monitor-names;
in {
  imports = [
    flake.homeModules.required
    flake.homeModules.lil-scripts
    flake.homeModules.modern-coreutils-replacements
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.wezterm
    flake.homeModules.qutebrowser
    flake.homeModules.zellij
    flake.homeModules.starship
    flake.homeModules.zsh
    flake.homeModules.nushell
    flake.homeModules.hyprland
    flake.homeModules.sway
    flake.homeModules.waybar
    flake.homeModules.wayvnc
    flake.homeModules.nix-index
    flake.homeModules.syncthing
    flake.homeModules.atuind
    flake.homeModules.claude-code
    flake.homeModules.llm
    flake.homeModules.jj
    flake.homeModules.pi
    flake.homeModules.codex
    flake.homeModules.optnix
    flake.homeModules.aoe
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.11";
  };

  gio.role = "desktop";

  programs.home-manager.enable = true;

  # Configure waybar for sway
  gio.waybar = {
    enable = true;
    windowManager = "sway";
    fontSize = 20;
    package = perSystem.giopkgs.waybar;
    audioOutputSwitcher = true;
    modules = {
      left = ["sway/mode" "sway/workspaces"];
      right = ["network" "network-graphs" "cpu" "memory" "custom/claude-usage" "pulseaudio" "tray" "custom/notification" "clock" "custom/power"];
    };
    monitors = {
      main = monitor-names.middle;
      secondary = [monitor-names.left monitor-names.right];
    };
    networkInterfaces = [
      {name = "enp0*";}
    ];
  };

  # Configure nix-activate for NixOS
  gio.nix-activate-config.activation = {
    system = "nixos";
  };

  # Configure Claude Code
  programs.gio-claude-code = {
    enable = true;
    installPackage = true;
  };

  # Setup fonts
  fonts = {
    fontconfig.enable = true;
  };
}
