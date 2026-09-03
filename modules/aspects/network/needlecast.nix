# needlecast — reach the other machine's localhost over a WireGuard tunnel.
# Trial pairing: cadmium serves its loopback ports in 8000-8999, cesium reaches
# them. Both halves derive their keypairs from one shared secret, so the same
# file must exist byte-for-byte on both machines; it is loaded as a systemd
# credential and never enters the store.
{inputs, ...}: let
  secretFile = "/var/lib/needlecast/secret";
in {
  den.aspects.needlecast-server.nixos = _: {
    imports = [inputs.needlecast.nixosModules.default];

    services.needlecast.server = {
      enable = true;
      # Only used for an initial resolve — the endpoint is relearned from the
      # client's handshake, so a travelling cesium does not need to be nameable.
      peer = "cesium.gio.ninja";
      inherit secretFile;
    };
  };

  den.aspects.needlecast-client.nixos = _: {
    imports = [inputs.needlecast.nixosModules.default];

    services.needlecast.client = {
      enable = true;
      peer = "cadmium.gio.ninja";
      inherit secretFile;
    };
  };
}
