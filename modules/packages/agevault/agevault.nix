{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    agevault = inputs.self.lib.writeNushellApplication pkgs {
      name = "agevault";
      runtimeInputs = with pkgs; [age openssh coreutils];
      source = builtins.readFile ./agevault.nu;

      passthru.tests.vm = pkgs.testers.runNixOSTest (import ./_test.nix {inherit agevault;});

      meta.description = "age-backed secret manager: encrypt at rest, deliver to hosts' credstore over ssh";
      meta.platforms = pkgs.lib.platforms.linux;
      meta.mainProgram = "agevault";
    };
  in {
    packages.agevault = agevault;

    checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
      agevault-vm = agevault.passthru.tests.vm;
    };
  };
}
