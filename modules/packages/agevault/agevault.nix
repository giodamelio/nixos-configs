{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;

    nuApp = inputs.self.lib.writeNushellApplication pkgs {
      name = "agevault";
      runtimeInputs = with pkgs; [age openssh coreutils];
      source = builtins.readFile ./agevault.nu;
    };

    # Per-shell completions (dynamic host/secret names, read from the vault on
    # disk). Shipped in share/ so devshells surface them via XDG_DATA_DIRS.
    completions = pkgs.runCommandLocal "agevault-completions" {} ''
      install -Dm444 ${./completions/_agevault}     "$out/share/zsh/site-functions/_agevault"
      install -Dm444 ${./completions/agevault.bash} "$out/share/bash-completion/completions/agevault"
      install -Dm444 ${./completions/agevault.fish} "$out/share/fish/vendor_completions.d/agevault.fish"
      install -Dm444 ${./completions/agevault.nu}   "$out/share/nushell/vendor/autoload/agevault.nu"
    '';

    agevault = pkgs.symlinkJoin {
      name = "agevault";
      paths = [nuApp completions];

      passthru.tests.vm = pkgs.testers.runNixOSTest (import ./_test.nix {inherit agevault;});

      meta = {
        description = "age-backed secret manager: encrypt at rest, deliver to hosts' credstore over ssh";
        platforms = lib.platforms.linux;
        mainProgram = "agevault";
      };
    };
  in {
    packages.agevault = agevault;

    checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
      agevault-vm = agevault.passthru.tests.vm;
    };
  };
}
