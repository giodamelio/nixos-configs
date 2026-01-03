{
  pkgs,
  flake,
  ...
}: {
  home.packages = [
    (pkgs.python3.withPackages (python-pkgs:
      with python-pkgs; [
        llm

        # External AI Providers
        llm-anthropic
        llm-gemini
        llm-openrouter
        llm-deepseek

        # Tools
        llm-tools-datasette
        llm-tools-sqlite

        # Fragment/template loaders
        llm-templates-github
        llm-fragments-github
      ]))

    flake.packages.${pkgs.stdenv.hostPlatform.system}.runprompt
  ];
}
