{pkgs, ...}: let
  inherit (pkgs) lib;
  name = "windmill";
  version = "1.576.0";
in
  pkgs.stdenv.mkDerivation {
    inherit name version;

    src = pkgs.fetchurl {
      url = "https://github.com/windmill-labs/windmill/releases/download/v${version}/windmill-amd64";
      sha256 = "sha256-a2QLLbh9TK5nOcMMdX3VaS9KBS0ihjABNMIrMPbbqFM=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      openssl
    ];

    phases = ["installPhase" "fixupPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/windmill
      chmod +x $out/bin/windmill
    '';

    postFixup = with pkgs; ''
      wrapProgram "$out/bin/windmill" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [stdenv.cc.cc]} \
        --prefix PATH : ${
        lib.makeBinPath [
          # uv searches for python on path as well!
          python312

          procps # bash_executor
          coreutils # bash_executor
        ]
      } \
        --set PYTHON_PATH "${python312}/bin/python3" \
        --set GO_PATH "${go}/bin/go" \
        --set DENO_PATH "${deno}/bin/deno" \
        --set NSJAIL_PATH "${nsjail}/bin/nsjail" \
        --set FLOCK_PATH "${flock}/bin/flock" \
        --set BASH_PATH "${bash}/bin/bash" \
        --set POWERSHELL_PATH "${powershell}/bin/pwsh" \
        --set BUN_PATH "${bun}/bin/bun" \
        --set UV_PATH "${python312Packages.uv}/bin/uv" \
        --set DOTNET_PATH "${dotnet-sdk_9}/bin/dotnet" \
        --set DOTNET_ROOT "${dotnet-sdk_9}/share/dotnet" \
        --set PHP_PATH "${php}/bin/php" \
        --set CARGO_PATH "${cargo}/bin/cargo"
    '';

    meta = with pkgs.lib; {
      description = "Open-source developer platform to turn scripts into workflows and UIs";
      homepage = "https://www.windmill.dev";
      platforms = platforms.linux;
      mainProgram = "windmill";
    };
  }
