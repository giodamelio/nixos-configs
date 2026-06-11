{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    credsync = inputs.self.lib.writeNushellApplication pkgs {
      name = "credsync";
      runtimeInputs = with pkgs; [systemd openssh coreutils];
      stdin = true;
      source = builtins.readFile ./credsync.nu;

      passthru.tests.vm = pkgs.testers.runNixOSTest (import ./_test.nix {inherit credsync;});

      meta.description = "Idempotently copy systemd-creds between hosts over SSH";
      meta.platforms = pkgs.lib.platforms.linux;
      meta.mainProgram = "credsync";
    };
  in {
    packages.credsync = credsync;

    checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
      credsync-vm = credsync.passthru.tests.vm;
    };
  };
}
