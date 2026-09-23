{inputs, ...}: {
  den.aspects.niks3-client.nixos = {
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    serverUrl = "https://cache.gio.ninja";
  in {
    imports = [inputs.niks3.nixosModules.niks3-auto-upload];

    services.niks3-auto-upload = {
      inherit serverUrl;
      enable = true;
      authTokenFile = "/run/credentials/niks3-auto-upload.service/niks3_api_token";
    };

    fleet.credentials.needs = ["niks3_api_token"];
    systemd.services.niks3-auto-upload.serviceConfig.LoadCredentialEncrypted = ["niks3_api_token"];

    environment.systemPackages = [
      perSystem.niks3.niks3

      # The token is only readable inside a unit that loads it, so run the CLI
      # as one rather than staging the blob anywhere.
      (pkgs.writeShellScriptBin "niks3-fleet" ''
        if [ $# -eq 0 ]; then
          exec ${lib.getExe perSystem.niks3.niks3} --help
        fi
        exec systemd-run \
          --quiet --pipe --wait --collect --same-dir \
          --service-type=exec \
          --property=LoadCredentialEncrypted=niks3_api_token \
          -- ${pkgs.bash}/bin/bash -c '
            # niks3 takes the subcommand first and parses flags after it.
            sub="$1"; shift
            exec ${lib.getExe perSystem.niks3.niks3} "$sub" \
              --server-url ${serverUrl} \
              --auth-token-path "$CREDENTIALS_DIRECTORY/niks3_api_token" \
              "$@"
          ' -- "$@"
      '')
    ];
  };
}
