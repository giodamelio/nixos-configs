# attic binary cache on gallium. The old gio.credentials envfile-wrapper is
# replaced by a fleet.secrets credential use-site (LoadCredentialEncrypted on
# atticd.service) + atticd's native environmentFile pointing at the credential
# path — systemd reads the env file directly, no ExecStart wrapper. Converted
# from nix/hosts/gallium/attic.nix.
#
# NOTE: the secret blob is a flat KEY=value env file. It CANNOT be handed to
# EnvironmentFile= directly from /run/credentials: systemd loads environment
# files when it spawns each Exec* line, before that invocation's credentials
# exist, so the path is always missing ("Failed to load environment files") and
# the unit restart-loops. Verified on gallium with a minimal transient unit.
# Instead ExecStartPre stages the credential into a RuntimeDirectory and
# EnvironmentFile= reads that, with `-` so its absence during ExecStartPre
# itself is not fatal.
_: {
  den.aspects.gallium.nixos = {
    pkgs,
    config,
    lib,
    ...
  }: let
    envPath = "/run/atticd/env";

    stageEnv = pkgs.writeShellApplication {
      name = "atticd-stage-env";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        install -m0400 "$CREDENTIALS_DIRECTORY/attic-envfile" ${envPath}
      '';
    };
  in {
    environment.systemPackages = with pkgs; [
      attic-client

      # atticadm wrapper that loads the encrypted credential via a transient unit.
      (pkgs.writeShellScriptBin "atticd-atticadm" ''
        exec systemd-run \
          --quiet \
          --pipe \
          --pty \
          --same-dir \
          --wait \
          --collect \
          --service-type=exec \
          --property=LoadCredentialEncrypted=attic-envfile \
          --property=DynamicUser=yes \
          --property=User=${config.services.atticd.user} \
          --property=Environment=ATTICADM_PWD=$(pwd) \
          --working-directory / \
          -- \
          ${pkgs.bash}/bin/bash -c '
            # Source the credential file if it exists
            if [ -f "''${CREDENTIALS_DIRECTORY}/attic-envfile" ]; then
              set -a
              . "''${CREDENTIALS_DIRECTORY}/attic-envfile"
              set +a
            fi
            exec ${config.services.atticd.package}/bin/atticadm "$@"
          ' -- "$@"
      '')
    ];

    services.atticd = {
      enable = true;
      # Staged from the fleet.secrets credential by ExecStartPre (see the note at
      # the top). The module asserts this is non-null, so it stays set even
      # though serviceConfig.EnvironmentFile is what systemd actually reads.
      environmentFile = envPath;
      settings = {
        storage = {
          type = "local";
          path = "/tank/attic_storage";
        };
      };
    };

    systemd.services.atticd.serviceConfig = {
      RuntimeDirectory = "atticd";
      ExecStartPre = lib.getExe stageEnv;
      # `-`: absent while ExecStartPre itself is spawned, populated by the time
      # ExecStart is. The module sets this unprefixed, hence mkForce.
      EnvironmentFile = lib.mkForce "-${envPath}";
    };
  };

  # attic.gio.ninja -> localhost:8080 + consul registration/health check.
  den.hosts.x86_64-linux.gallium.services.attic = {
    endpoint = {
      domain = "attic";
      backend.host = "localhost";
      backend.port = 8080;
    };
    healthcheck.target = "https://attic.gio.ninja/";
  };

  # Encrypted env file delivered to atticd.service as a systemd credential.
  fleet.secrets."attic-envfile" = {
    origin = "gallium";
    use.gallium.services.atticd.type = "credential";
  };
}
