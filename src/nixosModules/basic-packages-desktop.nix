_: {pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      bitwarden-cli
      bitwarden-menu
      thunderbird
      obsidian
      pavucontrol
      qutebrowser
    ];
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
