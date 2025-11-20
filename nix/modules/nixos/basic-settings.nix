{inputs, ...}: {
  environment.etc."issue.d/ip.issue".text = "IP Address \\4\n\n";
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      extra-experimental-features = ["pipe-operators"];
      trusted-users = ["root" "@wheel"];
      substituters = [
        "https://attic.gio.ninja/homelab"
      ];
      trusted-public-keys = [
        "homelab:Pin5h4Ny1Fkj1dpp7OA7COvhiKNHMFT9oSrQKhyXh0c="
      ];
    };
    registry = {
      stable.flake = inputs.nixpkgs-stable;
    };
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
