# pipewire — audio stack with realtime scheduling. Converted from
# nix/modules/nixos/pipewire.nix.
_: {
  den.aspects.pipewire.nixos = {pkgs, ...}: {
    # Realtime scheduling for PipeWire
    security.rtkit.enable = true;

    hardware.firmware = [pkgs.sof-firmware];

    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
  };
}
