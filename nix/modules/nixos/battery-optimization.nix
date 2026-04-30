_: {
  # TLP for overall power management
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      # WiFi power saving on battery
      WIFI_PWR_ON_BAT = "on";
    };
  };

  # TLP conflicts with power-profiles-daemon
  services.power-profiles-daemon.enable = false;

  # Intel thermal management
  services.thermald.enable = true;

  # Apply powertop recommended kernel tunables at boot
  powerManagement.powertop.enable = true;
}
