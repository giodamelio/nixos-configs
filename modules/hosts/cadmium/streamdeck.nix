_: {
  den.aspects.cadmium-streamdeck.nixos = {
    # The symlink survives replug, where the hidraw number changes. jailed-claude
    # only dev-binds devices under /dev/jail, so this rule is the allowlist.
    services.udev.extraRules = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0084", TAG+="uaccess", SYMLINK+="jail/streamdeck-plus"
    '';
  };
}
