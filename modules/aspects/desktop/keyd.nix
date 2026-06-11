# keyd — capslock as control-when-held / escape-when-tapped (and esc becomes
# capslock). Converted from nix/modules/nixos/keyd.nix. cesium carries its own
# Chromebook-specific keyd config in its host aspect instead of this one.
_: {
  den.aspects.keyd.nixos = {
    services.keyd = {
      enable = true;

      keyboards.default = {
        ids = ["*"];
        settings = {
          main = {
            # Make capslock be control when held and escape when tapped
            capslock = "overload(control, esc)";

            # Make esc be capslock
            esc = "capslock";
          };
        };
      };
    };
  };
}
