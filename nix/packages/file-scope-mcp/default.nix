{pkgs, ...}: let
  inherit (pkgs) lib;
  version = "2.8.0";
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "admica";
    repo = "FileScopeMCP";
    rev = version;
    hash = "sha256-AydAy0euzom+NjVKgr5gMX6XJnhome14oNbRvGHkbjE=";
  };
in
  pkgs.buildNpmPackage {
    pname = "file-scope-mcp";
    inherit version;

    src = pkgs.runCommandLocal "file-scope-mcp-src-with-lockfile.tar.gz" {} ''
      mkdir unpack
      cp -r ${upstreamSrc}/* unpack/
      cp ${./package-lock.json} unpack/package-lock.json
      tar -czf $out/file-scope-mcp-src.tar.gz --owner=0 --group=0 --format=gnu -C unpack .
      cp $out/file-scope-mcp-src.tar.gz $out
    '';

    npmDepsHash = pkgs.lib.fakeHash;

    nativeBuildInputs = [pkgs.jq];

    # postPatch = ''
    #   # Load our vendored lockfile
    #   cp ${./package-lock.json} ./package-lock.json
    #
    #   # Add a bin file to the package json so npm pack generates a bin
    #   # jq '.bin = (.bin // {}) + {"file-scope-mcp": "./dist/mcp-server.js"}' package.json > package.json.new
    #   # mv package.json.new package.json
    # '';

    # Run the build script
    # postBuild = ''
    #   npm run build
    # '';

    meta = {
      description = "Analyzes your codebase identifying important files based on dependency relationships. Generates diagrams and importance scores per file, helping AI assistants understand the codebase. Automatically parses popular programming languages such as Python, C, C++, Rust, Zig, Lua";
      homepage = "https://github.com/admica/FileScopeMCP.git";
      license = lib.licenses.gpl3Only;
      maintainers = with lib.maintainers; [];
      mainProgram = "file-scope-mcp";
      inherit (lib.platforms) all;
    };
  }
