# remote-builder-builder — the builder side of the remote-build pair (cadmium
# accepts builds; cesium's remote-builder-user is the client side). Converted
# from nix/modules/nixos/remote-builder-builder.nix.
_: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
  restrictKey = key: ''no-port-forwarding,no-X11-forwarding,no-agent-forwarding ${key}'';
in {
  den.aspects.remote-builder-builder.nixos = {
    users.users.nix-remote-builder = {
      isNormalUser = true;
      home = "/home/nix-remote-builder";
      openssh.authorizedKeys.keys = map restrictKey homelab.remote_builder_keys;
    };

    nix.settings.trusted-users = ["nix-remote-builder"];

    # Limit remote builder to half the CPU so local work isn't starved
    systemd.slices."user-nix\\x2dremote\\x2dbuilder" = {
      sliceConfig = {
        CPUQuota = "600%";
      };
    };
  };
}
