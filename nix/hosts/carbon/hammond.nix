{inputs, ...}: {
  imports = [
    inputs.hammond.nixosModules.default
  ];

  services.hammond = {
    enable = true;
  };

  gio.credentials = {
    enable = true;
    services = {
      "hammond" = {
        loadCredentialEncrypted = ["mealie_token" "discord_token"];
      };
    };
  };
}
