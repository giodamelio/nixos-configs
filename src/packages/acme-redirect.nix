{lib, ...}: {pkgs, ...}:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "acme-redirect";
  version = "0.6.2";

  src = pkgs.fetchFromGitHub {
    owner = "kpcyrd";
    repo = "acme-redirect";
    rev = "v${version}";
    hash = "sha256-d9grHPTiGyyHN5HID+5C9HLja8JtHRuZBNaFwg2EM7s=";
  };

  cargoHash = "sha256-Trir77jFzioe0dHtDSXBp0tGyAoaFjQdKjR+AnxEe0M=";

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];

  buildInputs = with pkgs;
    [
      openssl
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.Security
    ];

  meta = with lib; {
    description = "Tiny http daemon that answers acme challenges and redirects everything else to https";
    homepage = "https://github.com/kpcyrd/acme-redirect";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [];
    mainProgram = "acme-redirect";
  };
}
