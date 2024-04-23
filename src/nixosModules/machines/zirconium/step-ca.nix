_: {pkgs, ...}: {
  # Install the Smallstep CLI for CA management
  environment.systemPackages = [pkgs.step-cli];

  # Setup a user for the data
  users.users.step = {
    isSystemUser = true;
    group = "step";
    useDefaultShell = true;

    # Make a private home directory
    home = "/var/lib/step";
    homeMode = "700";
    createHome = true;
  };
  users.groups.step = {};

  # Setup data path so the CLI knows where to find stuff
  environment.variables.STEPPATH = "/var/lib/step/";

  # Run the CA server
  systemd.services.step-ca = {
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = "step";
      Group = "step";
      LoadCredentialEncrypted = "stepca-intermediate-password";
      ExecStart = "${pkgs.step-ca}/bin/step-ca /var/lib/step/config/ca.json --password-file \${CREDENTIALS_DIRECTORY}/stepca-intermediate-password";
    };
  };

  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [7443];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [7443];
  };
}
