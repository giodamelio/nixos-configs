{pkgs, ...}:
pkgs.buildGoModule {
  pname = "gradient-deployer";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-6PevAuIkjQ1XFmO9X0z3YlssCMxRgE512P3Duiw0WPg=";

  meta.mainProgram = "gradient-deployer";
}
