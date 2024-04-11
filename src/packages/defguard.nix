{lib, ...}: {pkgs, ...}: let
  coreVersion = "0.10.0";
  coreSrc = pkgs.fetchFromGitHub {
    owner = "DefGuard";
    repo = "defguard";
    rev = "v${coreVersion}";
    hash = "sha256-W0Sz02wfIbPt6FaE9gsiAGG6efqWjX0jWjJU+NVIt6E=";
    fetchSubmodules = true;
  };
in {
  # This is a unholy thing that extracts the files we want
  # directly from a docker image layer fetched from ghcr.io
  # Here Be Dragons
  ui = pkgs.stdenv.mkDerivation rec {
    pname = "defguard-docker-image";
    version = "sha256:6a918ab950ee8623532940b03cc991494de2e42f74ed7292e6d734193d3f2c71"; # Image Digest

    # We don't have a source, so don't unpack it
    dontUnpack = true;

    # Download the image contents with skopeo
    installPhase = ''
      mkdir $out image/ tmp/
      ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://ghcr.io/defguard/defguard@${version} dir:image

      # Unpack some layers
      tar xzfv image/0450d7b8e96ca65e77ca9b13c805b36c85d54649c4ae9b25f763dea3e8ba23bb -C tmp/
      tar xzfv image/e13343b5b9997a2b56ea40746ddf1c6b3a783904b019a7ca4873240b78244f94 -C tmp/

      # Copy the files we want
      cp -R tmp/app/web/dist/* $out/
      cp -R tmp/app/web/src/shared/images/svg/ $out/
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-QVxnUmcakQ+NZGtukJVEb5JT8EuBv725nqBe0iEDOkc=";
  };
  core = pkgs.rustPlatform.buildRustPackage {
    pname = "defguard";
    version = coreVersion;

    src = coreSrc;

    cargoHash = "sha256-uQ7OouPrjUzF2CbX8ipgf01tmxdNSrSxjoISrpIWCgU=";

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

    postInstall = ''
      cp ${coreSrc}/user_agent_header_regexes.yaml $out/
    '';

    meta = with lib; {
      description = "Enterprise, fast, secure VPN & SSO platform with hardware keys, 2FA/MFA";
      homepage = "https://github.com/DefGuard/defguard";
      license = licenses.asl20;
      maintainers = with maintainers; [giodamelio];
      mainProgram = "defguard";
    };
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
