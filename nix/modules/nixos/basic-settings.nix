{
  environment.etc."issue.d/ip.issue".text = "IP Address \\4\n\n";
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    extra-experimental-features = ["pipe-operators"];
    trusted-users = ["root" "@wheel"];
  };
  security.sudo.wheelNeedsPassword = false;
  security.pam.services.swaylock = {};
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
}
