{
  pkgs, ...
}: let
  lib = pkgs.lib;
in pkgs.buildGoModule rec {
  pname = "mcp-language-server";
  version = "0.1.1";

  src = pkgs.fetchFromGitHub {
    owner = "isaacphi";
    repo = "mcp-language-server";
    rev = "v${version}";
    hash = "sha256-T0wuPSShJqVW+CcQHQuZnh3JOwqUxAKv1OCHwZMr7KM=";
  };

  vendorHash = "sha256-3NEG9o5AF2ZEFWkA9Gub8vn6DNptN6DwVcn/oR8ujW0=";

  doCheck = false;
  excludedPackages = ["./integrationtests"];
  ldflags = [ "-s" "-w" ];

  meta = {
    description = "Mcp-language-server gives MCP enabled clients access semantic tools like get definition, references, rename, and diagnostics";
    homepage = "https://github.com/isaacphi/mcp-language-server";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "mcp-language-server";
  };
}
