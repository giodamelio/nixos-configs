_: {
  config,
  lib,
  pkgs,
  ...
}: {
  environment.etc."issue.d/ip.issue".text = "\\4{eth0}\n";
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "@wheel"];
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  security.pam.services.swaylock = {};
}
