# codex — install both OpenAI Codex and the just-every fork.
_: {
  den.aspects.codex.homeManager = {
    pkgs,
    perSystem,
    ...
  }: let
    everyCode = perSystem.just-every-code.default.overrideAttrs (old: {
      cargoDeps = pkgs.rustPlatform.importCargoLock {
        lockFile = "${old.src}/code-rs/Cargo.lock";
        outputHashes = {
          "mcp-types-0.0.0" = "sha256-BGpEuNXky7neVIQQHqyqRjoa/wemfp6zj+usJlkRN+g=";
          "ratatui-0.29.0" = "sha256-HBvT5c8GsiCxMffNjJGLmHnvG77A6cqEL+1ARurBXho=";
          "runfiles-0.1.0" = "sha256-uJpVLcQh8wWZA3GPv9D8Nt43EOirajfDJ7eq/FB+tek=";
        };
      };
    });
  in {
    home.packages = [
      perSystem.llm-agents.codex
      (pkgs.writeShellApplication {
        name = "codex-every";
        text = ''
          exec ${everyCode}/bin/codex "$@"
        '';
      })

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
