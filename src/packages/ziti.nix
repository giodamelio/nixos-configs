{lib, ...}: {pkgs, ...}:
pkgs.buildGoModule rec {
  pname = "ziti";
  version = "0.32.2";

  src = pkgs.fetchFromGitHub {
    owner = "openziti";
    repo = "ziti";
    rev = "v${version}";
    hash = "sha256-Me8Mx/G39b+FmlMpztLtholY72Mt2gW8ZwsXfO6BTgw=";
  };

  vendorHash = "sha256-I5BNfgU13X9iMCa/YnseEQggDFpl5tmvHlscZjo7At4=";

  buildInputs = with pkgs; [
    libpcap
  ];

  excludedPackages = [
    "zititest"
  ];

  ldflags = ["-s" "-w"];

  meta = with lib; {
    description = "The parent project for OpenZiti. Here you will find the executables for a fully zero trust, application embedded, programmable network @OpenZiti";
    homepage = "https://github.com/openziti/ziti";
    changelog = "https://github.com/openziti/ziti/blob/${src.rev}/CHANGELOG.md";
    license = licenses.asl20;
    maintainers = with maintainers; [giodamelio];
    mainProgram = "ziti";
  };
}
