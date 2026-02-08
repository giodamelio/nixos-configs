{
  inputs,
  flake,
  ...
}: {
  environment.etc."issue.d/ip.issue".text = "IP Address \\4\n\n";
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      extra-experimental-features = ["pipe-operators"];
      trusted-users = ["root" "@wheel"];
      substituters = [
        "https://cache.nixos.org"
        "https://attic.gio.ninja/homelab"
        "https://nix-community.cachix.org"
        "https://giopkgs.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "homelab:Pin5h4Ny1Fkj1dpp7OA7COvhiKNHMFT9oSrQKhyXh0c="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "giopkgs.cachix.org-1:8oiYAit71TVQVQgzOWkbwsJZwvf89Yymi5Sx+BaEdEs="
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

  # Copy the flake source to /etc/nixos for emergency recovery
  # In case of losing access to the main repo, any machine can rebuild itself with:
  #   cp -rL /etc/nixos /tmp/recovery && cd /tmp/recovery && nixos-rebuild switch --flake .#hostname
  environment.etc."nixos".source = flake;
  environment.etc."nixos-revision".text = flake.rev or flake.dirtyRev or "unknown";
}
