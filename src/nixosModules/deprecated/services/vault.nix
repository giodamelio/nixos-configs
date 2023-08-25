_: {pkgs, ...}: let
  runOnRebootScript = pkgs.writeShellApplication {
    name = "unlock-vault-after-reboot";
    runtimeInputs = with pkgs; [vault];
    text = ''
      # Make sure this script is running as root
      if [ "$EUID" -ne 0 ]
      then
          echo "Please run this as root or with sudo"
          exit 2
      fi

      # Set the vault address
      export VAULT_ADDR="http://127.0.0.1:8200";

      # Unseal the vault if it is sealed
      vault status > /dev/null
      if [ $? -eq 2 ]; then
        vault operator unseal
      fi

      # Read the vault token if it is not already set
      if [ ! -v VAULT_TOKEN ]; then
        read -rs -p "Input root token or token with policy admin/manage-approles: " VAULT_TOKEN
        export VAULT_TOKEN
        echo
        echo
      fi

      # Write some secrets out for the Vault agents
      vault read auth/approle/role/agent-lldap > /dev/null
      if [ $? -eq 2 ]; then
        echo "AppRole 'agent-lldap' does not exist. Cannot write secrets."
      else
        SECRET_LOCATION="/var/run/credentials/vault-agent-lldap"
        echo "Writing Secrets for vault-agent-lldap to $SECRET_LOCATION"
        mkdir -p $SECRET_LOCATION
        chmod 0600 $SECRET_LOCATION
        vault read -field=role_id auth/approle/role/agent-lldap/role-id > $SECRET_LOCATION/role_id
        vault write -field=secret_id -force auth/approle/role/agent-lldap/secret-id > $SECRET_LOCATION/secret_id
      fi
    '';
  };
in {
  environment = {
    systemPackages = with pkgs; [
      vault
      runOnRebootScript
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
