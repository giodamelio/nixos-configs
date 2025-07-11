{
  networking = {
    networkmanager.enable = true;
  };

  # Add user to group
  users.users.giodamelio.extraGroups = ["networkmanager"];
}
