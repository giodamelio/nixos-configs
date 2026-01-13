{
  pkgs,
  perSystem,
  ...
}: {
  home.packages = [
    # Fork of OpenAI Codex with extra stuff
    # https://github.com/just-every/code
    perSystem.just-every-code.default

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
}
