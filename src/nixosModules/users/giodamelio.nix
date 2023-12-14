{homelab, ...}: {pkgs, ...}: {
  users.users.giodamelio = {
    extraGroups = ["wheel"];
    isNormalUser = true;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = homelab.ssh_keys;
  };
  programs.zsh.enable = true;
}
