# yubikey — PC/SC smartcard daemon (pcscd, incl. the CCID driver) plus
# age-plugin-yubikey, so workstations can use YubiKey PIV age identities.
_: {
  den.aspects.yubikey.nixos = {pkgs, ...}: {
    services.pcscd.enable = true;
    environment.systemPackages = [pkgs.age-plugin-yubikey];
  };
}
