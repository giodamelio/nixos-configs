{
  flake,
  pkgs,
  lib,
  ...
}: let
  jailedClaude = flake.packages.${pkgs.stdenv.hostPlatform.system}.jailed-claude;
in {
  programs.zed-editor = {
    enable = true;
    installRemoteServer = true;
    extensions = [
      "nix"
      "rust"
    ];
    userSettings = {
      agent_servers = {
        "claude-acp" = {
          env = {
            CLAUDE_CODE_EXECUTABLE = lib.getExe jailedClaude;
          };
        };
      };
    };
  };
}
