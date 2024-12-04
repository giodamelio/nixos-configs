_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    wezterm
    raycast
  ];

  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    taps = [];
    brews = [];
    casks = [
      "firefox"
      "firefox@developer-edition"
      "whatsapp"
      "sekey"
    ];
  };
}
