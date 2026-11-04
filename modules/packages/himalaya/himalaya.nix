_: {
  # agent-dms needs 2.2.x (read without marking seen, unquoted replies, JMAP
  # sends filed under Sent). Pinned: the next release renames every --json key.
  perSystem = {pkgs, ...}: {
    packages.himalaya = pkgs.himalaya.overrideAttrs (_old: rec {
      version = "2.2.1";
      src = pkgs.fetchFromGitHub {
        owner = "pimalaya";
        repo = "himalaya";
        rev = "v${version}";
        hash = "sha256-fYspChAGb0PLdsgP5GViAwp4NdmDXDyait0mpqIkGfQ=";
      };
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit src;
        hash = "sha256-KDsvF8wHMIEw+rjBJpUTgX6QIhcCMVjLWcPWklpxG3Q=";
      };
      # nixpkgs' postInstall targets 2.0's desktop file and manual/completion
      # flags; only agent-dms runs this build, so skip the extras.
      postInstall = "";
    });
  };
}
