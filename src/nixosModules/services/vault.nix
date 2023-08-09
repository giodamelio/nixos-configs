{...}: {pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      vault
    ];
    # Set the default address for the vault cli because we are not using TLS
    variables = {
      VAULT_ADDR = "http://127.0.0.1:8200";
    };
  };
  services.vault = {
    enable = true;
    storageBackend = "file";
  };
}
