{ pkgs, lib, ... }: {
  programs.zellij = {
    enable = true;
  };

  # Manually setup completions and not auto start
  # programs.zellij.enableZshIntegration just adds auto start
  programs.zsh.initExtra = lib.mkOrder 200 ''
    eval "$(${lib.getExe pkgs.zellij} setup --generate-completion zsh)"
  '';

  # Manually set KDL config string, since the HM module is not in great shape right now
  xdg.configFile."zellij/config.kdl".text = ''
    keybinds {
      // Replace quit with detach
      shared_except "locked" {
        bind "Ctrl q" { Detach; }
      }

      // Override so double Ctrl-o go straight to the session switcher
      shared_except "session" "locked" {
        bind "Ctrl o" {
          SwitchToMode "Session";
          LaunchOrFocusPlugin "session-manager" {
              floating true
              move_to_focused_tab true
          };
          SwitchToMode "Normal";
        }
      }
    }
  '';
}
