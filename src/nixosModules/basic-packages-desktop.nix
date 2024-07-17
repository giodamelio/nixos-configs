_: {pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      bitwarden-cli
      bitwarden-menu
      thunderbird
      # Currently broken
      # obsidian
      pavucontrol
      qutebrowser
      xdg-utils
      vlc
    ];
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
