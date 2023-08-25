{homelab, ...}: _: {
  users.users.server = {
    extraGroups = ["wheel"];
    isNormalUser = true;
    openssh.authorizedKeys.keys = homelab.ssh_keys;
  };
}
