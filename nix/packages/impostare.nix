{pkgs, ...}:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "impostare";
  version = "0.2.0";

  src = pkgs.fetchFromGitHub {
    owner = "giodamelio";
    repo = "impostare";
    rev = "v${version}";
    hash = "sha256-+b7dBz7LQ5djXtUj/0/lu49FBK1iy7YCRVEawnkJMrE=";
  };

  cargoHash = "sha256-HOQJ5Z3WJIcnoOCR8bjBoa9kWNCb1HG4bPZdnAr9/1c=";

  buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
    pkgs.darwin.apple_sdk.frameworks.CoreFoundation
    pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
  ];

  meta = with pkgs.lib; {
    description = "";
    homepage = "https://github.com/giodamelio/impostare";
    license = licenses.mit;
    maintainers = with maintainers; [giodamelio];
    mainProgram = "impostare";
  };
}
