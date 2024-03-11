_: {
  pkgs,
  lib,
  ...
}: let
  defguardVersion = "0.9.0";
  defguardSource = pkgs.fetchFromGitHub {
    owner = "DefGuard";
    repo = "defguard";
    rev = "v${defguardVersion}";
    hash = "sha256-RWNR+wf70lASEt+mJgkpCpr4cfgqVixPuUWEm8RRXiQ=";
    fetchSubmodules = true;
  };
  defguard = pkgs.rustPlatform.buildRustPackage rec {
    pname = "defguard";
    version = defguardVersion;

    src = defguardSource;

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
  defguardUI = pkgs.buildNpmPackage {
    pname = "defguard-ui";
    version = defguardVersion;

    src = "${defguardSource}/web";

    npmDepsHash = "sha256-xLQakloAjO/HToFKQ+OZCl01GKwqIn674yxHwfWiYnA=";

    # The prepack script runs the build script, which we'd rather do in the build phase.
    npmPackFlags = ["--ignore-scripts"];

    # pnpm building story is bad, so I just generated a npm lock for the project
    postPatch = ''
      cp ${./defguard-core-package-lock.json} package-lock.json
    '';

    preBuild = ''
      npm run generate-translation-types
    '';

    meta = with lib; {
      description = "Enterprise, fast, secure VPN & SSO platform with hardware keys, 2FA/MFA";
      homepage = "https://github.com/DefGuard/defguard";
      license = licenses.asl20;
      maintainers = with maintainers; [giodamelio];
      mainProgram = "defguard";
    };
  };
in {
  environment.systemPackages = with pkgs; [
    pgcli
    defguard
  ];

  # Create defguard user
  # users.users.defguard = {
  #   isNormalUser = true;
  #   home = "/var/lib/defguard";
  # };

  # Create PostgreSQL DB
  services.postgresql = {
    enable = true;

    ensureDatabases = [
      "defguard"
    ];
    ensureUsers = [
      {
        name = "defguard";
        ensureDBOwnership = true;
      }
    ];
  };

  # Run Defguard Core
  # virtualisation.oci-containers.containers.defguard-core = {
  #   image = "ghcr.io/defguard/defguard:0.9.1";
  #   autoStart = true;
  #   ports = [
  #     "8000:8000" # WebUI
  #   ];
  #   volumes = [
  #     "/run/postgresql:/run/postgresql"
  #   ];
  #   environment = {
  #     DEFGUARD_SECRET_KEY = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  #     DEFGUARD_AUTH_SECRET = "defguard-auth-secret";
  #     DEFGUARD_GATEWAY_SECRET = "defguard-gateway-secret";
  #     DEFGUARD_YUBIBRIDGE_SECRET = "defguard-yubibridge-secret";
  #     DEFGUARD_DB_HOST = "/run/postgresql";
  #   };
  # };

  # Override Defguard SystemD user
  systemd.services.podman-defguard-core = {
    serviceConfig = {
      User = "defguard";
    };
  };

  # Run DefGuard Core
  systemd.services.defguard-core = {
    description = "DefGuard Core";
    wantedBy = ["default.target"];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      User = "defguard";
      StateDirectory = "defguard";
      WorkingDirectory = "/var/lib/defguard";
    };
    environment = {
      DEFGUARD_SECRET_KEY = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
      DEFGUARD_AUTH_SECRET = "defguard-auth-secret";
      DEFGUARD_GATEWAY_SECRET = "defguard-gateway-secret";
      DEFGUARD_YUBIBRIDGE_SECRET = "defguard-yubibridge-secret";
      DEFGUARD_DB_HOST = "/run/postgresql";
    };
    script = ''
      # Download file needed at runtime
      ${pkgs.wget}/bin/wget https://github.com/DefGuard/defguard/raw/main/user_agent_header_regexes.yaml

      echo ${defguardUI}

      ${defguard}/bin/defguard
    '';
  };
}
