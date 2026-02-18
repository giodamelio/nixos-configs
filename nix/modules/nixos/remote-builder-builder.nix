{
  users.users.nix-remote-builder = let
    builderKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBCyh/3f4nbOmINaD+dLuU4/uOAKBNu/r3cXS/Jx4uqu root@hammond"
    ];
    restrictKey = key: ''command="nix-daemon --stdio",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ${key}'';
  in {
    isNormalUser = true;
    home = "/home/nix-remote-builder";
    openssh.authorizedKeys.keys = map restrictKey builderKeys;
  };

  nix.settings.trusted-users = ["nix-remote-builder"];
}
