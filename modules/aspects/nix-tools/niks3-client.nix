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
      (inputs.self.lib.writeNushellApplication pkgs {
        name = "niks3-fleet";
        runtimeInputs = [pkgs.systemd];
        # Env vars instead of flags: nested subcommands (`pins list`) only parse
        # flags after the last subcommand word.
        source = ''
          def --wrapped main [...args] {
            let unit = $"niks3-fleet-(random chars --length 8)"
            (systemd-run --quiet --pipe --wait --collect --same-dir --service-type=exec
              $"--unit=($unit)"
              --property=LoadCredentialEncrypted=niks3_api_token
              --setenv=NIKS3_SERVER_URL=${serverUrl}
              $"--setenv=NIKS3_AUTH_TOKEN_FILE=/run/credentials/($unit).service/niks3_api_token"
              -- ${lib.getExe perSystem.niks3.niks3} ...$args)
          }
        '';
      })
    ];
  };
}
