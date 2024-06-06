_: {pkgs, ...}:
pkgs.buildGoModule rec {
  pname = "ecsplorer";
  version = "0.0.7";

  src = pkgs.fetchFromGitHub {
    owner = "masaushi";
    repo = "ecsplorer";
    rev = "v${version}";
    hash = "sha256-TlsBW/SVOKTrMjLPyB+5twbr9CyUpAFG0xmCTPNjvSs=";
  };

  vendorHash = "sha256-lF7Y89VNXAP/a2ztW8zioAm+qMAb7aEtqOS5k7/ymdw=";

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/masaushi/ecsplorer/cmd.Version=${version}"
  ];

  meta = with pkgs.lib; {
    description = "Ecsplorer is a tool designed for easy CLI operations with AWS ECS";
    homepage = "https://github.com/masaushi/ecsplorer";
    license = licenses.mit;
    maintainers = with maintainers; [giodamelio];
    mainProgram = "ecsplorer";
  };
}
