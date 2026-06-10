{lib, ...}: {
  networking.useDHCP = lib.mkDefault true;
  networking.hostName = "calcium";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
