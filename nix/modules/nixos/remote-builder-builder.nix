_: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
  restrictKey = key: ''command="nix-daemon --stdio",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ${key}'';
in {
  users.users.nix-remote-builder = {
    isNormalUser = true;
    home = "/home/nix-remote-builder";
    openssh.authorizedKeys.keys = map restrictKey homelab.remote_builder_keys;
  };

  nix.settings.trusted-users = ["nix-remote-builder"];
}
