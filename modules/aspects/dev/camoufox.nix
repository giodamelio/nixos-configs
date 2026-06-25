# camoufox — anti-detect browser and automation tooling from camoufox-nix.
_: {
  den.aspects.camoufox.homeManager = {perSystem, ...}: let
    inherit (perSystem) camoufox-nix;
    # camoufox-bin is the prebuilt browser wrapper; its passthru exposes each
    # tool re-wired against that browser as camoufox-bin.<name>.
    inherit (camoufox-nix) camoufox-bin;
  in {
    home.packages = [
      camoufox-bin
      camoufox-bin.camoufox-browser-cli
      camoufox-bin.camofox-browser
      camoufox-bin.camofox-cli
      camoufox-bin.camofox-mcp
      # foxbridge takes no browser arg, so it has no wired camoufox-bin variant.
      camoufox-nix.foxbridge
      # vulpineos: broken upstream (source hash mismatch); re-add once fixed.
    ];
  };
}
