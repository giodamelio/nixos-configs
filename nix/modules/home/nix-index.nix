{
  inputs,
  pkgs,
  ...
}: let
  nix-index-update = pkgs.writeShellApplication {
    name = "nix-index-update";
    runtimeInputs = [pkgs.wget];
    text = ''
      mkdir -p "$HOME/.cache/nix-index"
      cd "$HOME/.cache/nix-index"
      filename="index-$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"
      wget -nv -N "https://github.com/nix-community/nix-index-database/releases/latest/download/$filename"
      ln -sf "$filename" files
    '';
  };
in {
  imports = [
    inputs.nix-index-database.homeModules.nix-index
  ];

  programs.nix-index-database.comma.enable = true;

  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  systemd.user.services.nix-index-update = {
    Unit = {
      Description = "Download the latest nix-index database";
      ConditionACPower = true;
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${nix-index-update}/bin/nix-index-update";
    };
  };

  systemd.user.timers.nix-index-update = {
    Unit.Description = "Download the latest nix-index database";
    Timer = {
      OnCalendar = "Wed *-*-* 02:00:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
    Install.WantedBy = ["timers.target"];
  };
}
