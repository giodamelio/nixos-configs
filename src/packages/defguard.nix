{lib, ...}: {pkgs, ...}: let
  downloadScript = version:
    pkgs.writeShellApplication {
      name = "download-layer";

      runtimeInputs = with pkgs; [curl jq cacert];

      text = ''
        # Make curl work with SSL
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

        # Get token so we can download layer
        token_url="https://ghcr.io/token?service=ghcr.io&scope=repository%3Adefguard%2Fdefguard%3Apull"
        token=$(curl "$token_url" | jq -r .token)

        # Download layer
        curl --fail --location --output layer.tar.gz "https://ghcr.io/v2/defguard/defguard/blobs/sha256:${version}" -H "authorization: Bearer $token"
      '';
    };
  extractScript = pkgs.writeShellApplication {
    name = "extract-layer";

    runtimeInputs = with pkgs; [gzip];

    text = ''
      tar xzfv layer.tar.gz

      # Allow access to $out even though it was not defined here
      # shellcheck disable=SC2154
      mkdir -p "$out/web/"

      # Allow access to $out even though it was not defined here
      # shellcheck disable=SC2154
      mv app/web/dist/ "$out/web/"
    '';
  };
  coreVersion = "0.9.0";
  coreSrc = pkgs.fetchFromGitHub {
    owner = "DefGuard";
    repo = "defguard";
    rev = "v${coreVersion}";
    hash = "sha256-RWNR+wf70lASEt+mJgkpCpr4cfgqVixPuUWEm8RRXiQ=";
    fetchSubmodules = true;
  };
in rec {
  # This is a unholy thing that extracts the files we want
  # directly from a docker image layer fetched from ghcr.io
  # Here Be Dragons
  ui = pkgs.stdenv.mkDerivation rec {
    pname = "defguard-ui";
    version = "f5e89529eba2786c8eab0b9e24ac1a5935299fab38286d34f8090f613b63e160"; # Blob digest
    src = ./.;

    buildPhase = "${downloadScript version}/bin/download-layer";
    installPhase = "${extractScript}/bin/extract-layer";

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-cari72NzwPMzyfoS+Wif1uYUKDEh6CG4oo7Kci8jt8E=";
  };
  core = pkgs.rustPlatform.buildRustPackage {
    pname = "defguard";
    version = coreVersion;

    src = coreSrc;

    cargoHash = "sha256-BzWw+rnXshXyxhERIT8XJRhhY2iJftAqy+3SmIFCT/0=";

    nativeBuildInputs = with pkgs; [
      pkg-config
      protobuf
    ];

    # Force SqlX offline mode so we don't need a DB to build
    SQLX_OFFLINE = true;

    # Don't run the tests
    doCheck = false;

    buildInputs = with pkgs;
      [
        openssl
        sqlite
      ]
      ++ lib.optionals stdenv.isDarwin [
        darwin.apple_sdk.frameworks.CoreFoundation
        darwin.apple_sdk.frameworks.Security
        darwin.apple_sdk.frameworks.SystemConfiguration
      ];

    meta = with lib; {
      description = "Enterprise, fast, secure VPN & SSO platform with hardware keys, 2FA/MFA";
      homepage = "https://github.com/DefGuard/defguard";
      license = licenses.asl20;
      maintainers = with maintainers; [giodamelio];
      mainProgram = "defguard";
    };
  };
  # The core binary bundled with the WebUI and supporting files
  core-bundled = pkgs.symlinkJoin {
    name = "defguard-core-bundled";
    paths = [
      # Main bin
      "${core}/bin/" # Main bin
      # Supporting File
      (lib.sources.sourceByRegex coreSrc ["user_agent_header_regexes.yaml"])
      # Compiled WebUI
      ui
    ];
  };
  gateway = pkgs.rustPlatform.buildRustPackage rec {
    pname = "defguard-gateway";
    version = "0.6.2";

    src = pkgs.fetchFromGitHub {
      owner = "DefGuard";
      repo = "gateway";
      rev = "v${version}";
      hash = "sha256-Mi0qZxDlh2DIoIJtNKL/E2hL+s4Tr62rpz+9FJXOSzE=";
      fetchSubmodules = true;
    };

    cargoLock = {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "defguard_wireguard_rs-0.4.2" = "sha256-GmutcOHlhh5NbPwaDI66H03tAQ0ze9lZqRZUwK2YYEE=";
      };
    };

    nativeBuildInputs = with pkgs; [
      protobuf
    ];

    buildInputs = lib.optionals pkgs.stdenv.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.Security
    ];

    meta = with lib; {
      description = "Defguard gateway";
      homepage = "https://github.com/DefGuard/gateway";
      license = licenses.asl20;
      maintainers = with maintainers; [giodamelio];
      mainProgram = "defguard-gateway";
    };
  };
}
