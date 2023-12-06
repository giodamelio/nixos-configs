{homelab, ...}: _: {
  users.users.giodamelio = {
    extraGroups = ["wheel"];
    isNormalUser = true;
    openssh.authorizedKeys.keys = homelab.ssh_keys;
  };
}
