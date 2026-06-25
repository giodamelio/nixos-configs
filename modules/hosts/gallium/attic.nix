# attic binary cache on gallium. The old gio.credentials envfile-wrapper is
# replaced by a fleet.secrets credential use-site (LoadCredentialEncrypted on
# atticd.service) + atticd's native environmentFile pointing at the credential
# path — systemd reads the env file directly, no ExecStart wrapper. Converted
# from nix/hosts/gallium/attic.nix.
#
# NOTE: the secret blob is a flat KEY=value env file read via EnvironmentFile=
# (the old wrapper shell-sourced it). atticd's env file is simple KEY=value so
# this is equivalent; revisit if it ever needs shell-expansion semantics.
_: {
  den.aspects.gallium.nixos = {
    pkgs,
    config,
    ...
  }: {
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
      # Env vars come from the fleet.secrets credential loaded onto this unit.
      environmentFile = "/run/credentials/atticd.service/attic-envfile";
      settings = {
        storage = {
          type = "local";
          path = "/tank/attic_storage";
        };
      };
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
