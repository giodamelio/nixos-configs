# basic-packages-desktop — GUI apps + 1Password GUI for desktop hosts.
# Converted from nix/modules/nixos/basic-packages-desktop.nix.
_: {
  den.aspects.basic-packages-desktop.nixos = {pkgs, ...}: {
    environment = {
      systemPackages = with pkgs; [
        thunderbird
        obsidian
        todoist-electron
        pavucontrol
        qutebrowser
        xdg-utils
        vlc
        firefox
        mpv
        kdePackages.okular
        zathura
        foot
        rpi-imager
      ];
      sessionVariables = {
        NIXOS_OZONE_WL = "1";
      };
    };

    programs._1password-gui = {
      enable = true;

      # Certain features, including CLI integration and system authentication support,
      # require enabling PolKit integration on some desktop environments (e.g. Plasma).
      polkitPolicyOwners = ["giodamelio"];
    };
  };
}
