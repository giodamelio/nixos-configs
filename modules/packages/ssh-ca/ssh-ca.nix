{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;

    ssh-ca = inputs.self.lib.writeNushellApplication pkgs {
      name = "ssh-ca";
      runtimeInputs = with pkgs; [step-cli openssh systemd jq openssl coreutils];
      source = builtins.readFile ./ssh-ca.nu;

      passthru.tests.vm = pkgs.testers.runNixOSTest (import ./_test.nix {inherit ssh-ca;});

      meta.description = "File-based SSH certificate authority (step-managed, no daemon)";
      meta.platforms = pkgs.lib.platforms.linux;
      meta.mainProgram = "ssh-ca";
    };

    # The ghost fixture's throws prove a disabled host's facts are never read.
    targets-test = let
      sshTypes = import ../../aspects/ssh/_types.nix {inherit lib;};
      fixtures = {
        alpha = {
          ssh = {
            enable = true;
            hostKey = "ssh-ed25519 AAAAalpha";
            extraPrincipals = ["vanity.gio.ninja"];
          };
          users.gio.ssh = {
            publicKey = "ssh-ed25519 AAAAgio";
            accessTo.beta.root = true;
          };
        };
        beta = {
          # Enabled but not enrolled: trusted client, no host cert.
          ssh = {
            enable = true;
            hostKey = null;
            extraPrincipals = [];
          };
          users = {};
        };
        ghost = {
          # Disabled = does not exist; nothing else may be read.
          ssh = {
            enable = false;
            hostKey = throw "ghost ssh.hostKey must not be read";
            extraPrincipals = throw "ghost ssh.extraPrincipals must not be read";
          };
          users = throw "ghost users must not be read";
        };
      };
      hostTargets = sshTypes.hostTargetsOf "gio.ninja" fixtures;
      identities = sshTypes.userIdentitiesOf fixtures;
    in
      assert hostTargets
      == {
        alpha = {
          pubkey = "ssh-ed25519 AAAAalpha";
          principals = ["alpha" "alpha.gio.ninja" "vanity.gio.ninja"];
        };
      };
      assert identities
      == [
        {
          name = "gio@alpha";
          publicKey = "ssh-ed25519 AAAAgio";
          accessTo.beta.root = true;
        }
      ];
      assert sshTypes.principalsOf (builtins.head identities) == ["root@beta"];
        pkgs.runCommand "ssh-ca-targets-test" {} "echo ok > $out";
  in {
    packages.ssh-ca = ssh-ca;

    checks =
      {
        ssh-ca-targets = targets-test;
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
        ssh-ca-vm = ssh-ca.passthru.tests.vm;
      };
  };
}
