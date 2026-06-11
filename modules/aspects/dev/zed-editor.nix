# zed-editor — Zed with the jailed-claude ACP agent. Converted from
# nix/modules/home/zed-editor.nix; the repo's own package is reached as
# `perSystem.self`.
_: {
  den.aspects.zed-editor.homeManager = {
    perSystem,
    lib,
    ...
  }: let
    jailedClaude = perSystem.self.jailed-claude;
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
  };
}
