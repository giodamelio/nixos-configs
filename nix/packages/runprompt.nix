{pkgs}: let
  inherit (pkgs) lib;
in
  pkgs.stdenv.mkDerivation {
    pname = "runprompt";
    version = "0.0.1";

    src = pkgs.fetchFromGitHub {
      owner = "chr15m";
      repo = "runprompt";
      rev = "255689ff567e304a717ae5521a30f691bb6a686a";
      hash = "sha256-fvHlsdKL0n2NlHKDqJZa8rROmJWNL4wOzKDEl3wU9lw=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      substituteInPlace runprompt \
        --replace-fail "#!/usr/bin/env python3" "#!${pkgs.python3}/bin/python3"

      install -Dm755 runprompt $out/bin/runprompt

      runHook postInstall
    '';

    meta = with lib; {
      description = "Tiny script to run .prompt files";
      homepage = "https://github.com/chr15m/runprompt";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "runprompt";
    };
  }
