{inputs, ...}: {
  den.aspects.niks3-client.nixos = {
    imports = [inputs.niks3.nixosModules.niks3-auto-upload];

    services.niks3-auto-upload = {
      enable = true;
      serverUrl = "https://cache.gio.ninja";
      authTokenFile = "/run/credentials/niks3-auto-upload.service/niks3_api_token";
    };

    fleet.credentials.needs = ["niks3_api_token"];
    systemd.services.niks3-auto-upload.serviceConfig.LoadCredentialEncrypted = ["niks3_api_token"];
  };
}
