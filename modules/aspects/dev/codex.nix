# codex — install both OpenAI Codex and the just-every fork.
_: {
  den.aspects.codex.homeManager = {
    pkgs,
    perSystem,
    ...
  }: {
    home.packages = [
      perSystem.llm-agents.codex
      perSystem.llm-agents.code

      # Codex uses Chrome, but I don't like having that installed.
      # So we fool it into using UnGoogled Chromium
      (pkgs.writeShellApplication {
        name = "google-chrome";
        runtimeInputs = [pkgs.ungoogled-chromium];
        text = ''
          exec ${pkgs.ungoogled-chromium}/bin/chromium "$@"
        '';
      })
    ];
  };
}
