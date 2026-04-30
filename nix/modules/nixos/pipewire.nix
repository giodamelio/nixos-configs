{pkgs, ...}: {
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
}
