_: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;

    bifrost = pkgs.buildGoModule {
      pname = "bifrost";
      version = "0.1.0";

      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./go.mod
          ./go.sum
          ./templates
          (lib.fileset.fileFilter (f: f.hasExt "go") ./.)
        ];
      };

      vendorHash = "sha256-v/Q2J1IqAqGFp5oN949Tu6qbbHs3A5+ws7POVGtWaSw=";

      passthru.tests.vm = pkgs.testers.runNixOSTest (import ./_test.nix {inherit bifrost;});

      meta = {
        description = "Caddy with the bifrost plugin: the guarded internet entry point";
        platforms = lib.platforms.linux;
        mainProgram = "caddy";
      };
    };
  in {
    packages.bifrost = bifrost;

    checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
      bifrost-vm = bifrost.passthru.tests.vm;
    };
  };
}
