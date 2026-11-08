_: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;
  in {
    packages.agent-dms-notify = pkgs.buildGoModule {
      pname = "agent-dms-notify";
      version = "0.1.0";

      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./go.mod
          (lib.fileset.fileFilter (f: f.hasExt "go") ./.)
        ];
      };

      vendorHash = null;

      meta = {
        description = "Stalwart MTA hook that mails the owner an approval request for held agent mail";
        platforms = lib.platforms.linux;
        mainProgram = "agent-dms-notify";
      };
    };
  };
}
