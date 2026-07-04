# todoist — Todoist desktop app + CLI.
_: {
  den.aspects.todoist.nixos = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      todoist-cli
      todoist-electron
    ];
  };
}
