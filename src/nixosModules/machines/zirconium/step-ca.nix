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
}
