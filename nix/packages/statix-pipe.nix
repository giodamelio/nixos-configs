{pkgs, ...}:
# REMIND-ME-TO: Switch back to pkgs.statix tag_exists=github:oppiliappan/statix@>=0.6.0
# Custom build of statix from after v0.5.8 that supports the |> pipe operator.
pkgs.rustPlatform.buildRustPackage {
  pname = "statix";
  version = "0.5.8-unstable";
  src = pkgs.fetchFromGitHub {
    owner = "oppiliappan";
    repo = "statix";
    rev = "f76adab8920438c39edbf3463b7a7150f9875617";
    sha256 = "sha256-g1fFexvaHiW4qc3XfVaoqoCe2mp1yeaDG4wgaDgcuGM=";
  };
  cargoHash = "sha256-jiMv28kSqCfaYnVsE/q/EtaPmSrANvJYjI9FQ2+Biz8=";
  buildFeatures = "json";
  meta.mainProgram = "statix";
  doCheck = !pkgs.stdenv.hostPlatform.isDarwin;
}
