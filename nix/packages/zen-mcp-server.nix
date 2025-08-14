{pkgs, ...}: let
  inherit (pkgs) python3 lib;
in
  pkgs.python3.pkgs.buildPythonApplication rec {
    pname = "zen-mcp-server";
    version = "unstable-2025-06-30";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "BeehiveInnovations";
      repo = "zen-mcp-server";
      rev = "ad6b21626566db9f04997584fd1b47897ff15ae5";
      hash = "sha256-6r1tm4o+gPeARnKn44UjKLfNYHG45WONJ50i8dOGI5k=";
    };

    build-system = [
      python3.pkgs.setuptools
      python3.pkgs.setuptools-scm
      python3.pkgs.wheel
    ];

    dependencies = with python3.pkgs; [
      google-genai
      mcp
      openai
      pydantic
      python-dotenv
    ];

    # Don't check imports since this isn't a traditional Python package
    pythonImportsCheck = [];

    meta = {
      description = "The power of Claude Code + [Gemini / OpenAI / Grok / OpenRouter / Ollama / Custom Model / All Of The Above] working as one";
      homepage = "https://github.com/BeehiveInnovations/zen-mcp-server";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [];
      mainProgram = "zen-mcp-server";
    };
  }
