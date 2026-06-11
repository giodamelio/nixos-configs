# zed-editor — Zed with the jailed-claude ACP agent.
_: {
  den.aspects.zed-editor.homeManager = {
    perSystem,
    lib,
    ...
  }: let
    jailedClaude = perSystem.self.jailed-claude;
  in {
    # Zed's CLI binary is named zeditor
    home.shellAliases.zed = "zeditor";

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
