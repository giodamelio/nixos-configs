{pkgs}: let
  inherit (pkgs) lib rustPlatform fetchFromGitHub curl pkg-config protobuf bzip2 oniguruma openssl zlib zstd stdenv darwin pnpm;

  version = "1.5.3";

  src = fetchFromGitHub {
    owner = "rustmailer";
    repo = "rustmailer";
    rev = version;
    hash = "sha256-FqIadANJHTJrxwMjFEG/GOPuNfjDmhYf1Mtge4FsUA8=";
  };

  pname = "rustmail";

  web = stdenv.mkDerivation {
    inherit version src;
    pname = "${pname}-web";

    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.pnpm.configHook
    ];

    pnpmDeps = pnpm.fetchDeps {
      inherit version src;
      pname = "${pname}-web";
      fetcherVersion = 2;
      hash = "sha256-G0kPcpZ8bZTrO++lSqxqD6SHRRmqmZl36G4HRyMps7w=";
      sourceRoot = "${src.name}/web";
    };

    # pnpmRoot = "web";
    sourceRoot = "${src.name}/web";

    buildPhase = ''
      runHook preBuild
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/* $out/
      runHook postInstall
    '';
  };
in
  rustPlatform.buildRustPackage rec {
    inherit src version pname;

    cargoHash = "sha256-Zw9kGUKlrpfkakH0YPaVIV51efzWFZzrX5E0H1EsLtQ=";

    nativeBuildInputs = [
      curl
      pkg-config
      protobuf
      rustPlatform.bindgenHook
    ];

    buildInputs =
      [
        bzip2
        curl
        oniguruma
        openssl
        zlib
        zstd
      ]
      ++ lib.optionals stdenv.isDarwin [
        darwin.apple_sdk.frameworks.IOKit
        darwin.apple_sdk.frameworks.Security
      ];

    patches = [./git-hash.patch];

    postPatch = ''
      mkdir -p web/dist
      cp -r ${web}/* web/dist/

      substituteInPlace build.rs \
        --replace-fail "@GIT_HASH@" "${version}"
    '';

    doCheck = false;

    env = {
      OPENSSL_NO_VENDOR = true;
      RUSTONIG_SYSTEM_LIBONIG = true;
      ZSTD_SYS_USE_PKG_CONFIG = true;
    };

    meta = {
      description = "A self-hosted Email Middleware for IMAP, SMTP, Gmail API, Graph API — built for developers";
      homepage = "https://github.com/rustmailer/rustmailer";
      license = lib.licenses.unfree;
      maintainers = with lib.maintainers; [];
      mainProgram = "rustmailer";
    };
  }
