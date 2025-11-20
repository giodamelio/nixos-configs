{
  pkgs,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [
    attic-client

    # Add our own version of the atticadm wrapper that works with credentials
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
    # Environment variables will be loaded from systemd cred
    environmentFile = "/dev/null";
    settings = {
      storage = {
        type = "local";
        path = "/tank/attic_storage";
      };
    };
  };

  gio.credentials = {
    enable = true;
    services = {
      "atticd" = {
        loadCredentialEncrypted = ["attic-envfile"];
        execStartWrapper = {
          envfiles = ["attic-envfile"];
        };
      };
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "attic" = {
        host = "localhost";
        port = 8080;
      };
    };
  };
}
