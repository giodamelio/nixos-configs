{
  pkgs,
  perSystem,
  ...
}:
perSystem.optnix.default.overrideAttrs (_: {
  patches = [
    (pkgs.fetchpatch
      {
        url = "https://github.com/water-sucks/optnix/compare/main...giodamelio:optnix:shift-tab-binding.patch";
        hash = "sha256-YqY2Aue4VBXL6T+yizG5AX2sLagLlH2MHUOcLVGpzBw=";
      })
  ];
})
