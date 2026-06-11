# basic-settings — Nix daemon settings, SSH hardening, the private Gradient
# cache netrc, and the /etc/nixos recovery copy. Converted from
# nix/modules/nixos/basic-settings.nix.
#
# This aspect needs two non-package flake values, so it closes over `inputs` at
# file scope (the explicit escape hatch — per-system only injects `perSystem`):
#   - `inputs.self` backs the /etc/nixos recovery copy + revision text (the
#     check-drv-drift harness strips these, since they bake the flake source
#     into the host).
#   - `inputs.nixpkgs-stable` backs the registry pin.
{inputs, ...}: {
  den.aspects.basic-settings.nixos = {
    lib,
    pkgs,
    ...
  }: {
    environment.etc."issue.d/ip.issue".text = "IP Address \\4\n\n";
    nix = {
      settings = {
        experimental-features = ["nix-command" "flakes"];
        extra-experimental-features = ["pipe-operators"];
        allow-import-from-derivation = true;
        trusted-users = ["root" "@wheel"];
        substituters = [
          "https://cache.nixos.org"
          "https://gradient.gio.ninja/cache/main"
          "https://attic.gio.ninja/homelab"
          "https://nix-community.cachix.org"
          "https://giopkgs.cachix.org"
          "https://noctalia.cachix.org"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "gradient.gio.ninja-main:Qx23IyI8Q9+FFl55YYptLSeTWUtFsF6bdK+I8Tma40Q="
          "homelab:Pin5h4Ny1Fkj1dpp7OA7COvhiKNHMFT9oSrQKhyXh0c="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "giopkgs.cachix.org-1:8oiYAit71TVQVQgzOWkbwsJZwvf89Yymi5Sx+BaEdEs="
          "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        ];

        # Dedicated netrc for private substituter auth (the Gradient cache),
        # assembled at boot under /run by gradient-cache-netrc.service. Pointing
        # at a runtime path keeps the decrypted token off persistent disk and out
        # of the machine's general /etc/nix/netrc. A missing file is harmless —
        # Nix just treats the private cache as unauthenticated and falls through.
        netrc-file = "/run/gradient-cache/netrc";
      };
      registry = {
        stable.flake = inputs.nixpkgs-stable;
        giopkgs.to = {
          type = "github";
          owner = "giodamelio";
          repo = "giopkgs";
        };
      };
    };
    # Authenticate to the private Gradient binary cache.
    #
    # The complete netrc (machine/login/password) is encrypted as a single
    # systemd-creds blob and decrypted at boot into /run/gradient-cache/netrc —
    # a tmpfs path used only by nix.settings.netrc-file, never written to disk.
    # ConditionPathExists makes hosts without the credential skip this cleanly
    # rather than failing, so it is safe to enable fleet-wide and roll the
    # credential out host by host.
    #
    # Place the credential per host (it is host-bound) with:
    #   printf 'machine gradient.gio.ninja\nlogin gradient\npassword <TOKEN>\n' \
    #     | systemd-creds encrypt --name=gradient-cache-netrc - \
    #         /usr/lib/credstore.encrypted/gradient-cache-netrc
    systemd.services.gradient-cache-netrc = {
      wantedBy = ["multi-user.target"];
      before = ["nix-daemon.service"];
      unitConfig.ConditionPathExists = "/usr/lib/credstore.encrypted/gradient-cache-netrc";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredentialEncrypted = "gradient-cache-netrc";
        RuntimeDirectory = "gradient-cache";
        RuntimeDirectoryPreserve = true;
        ExecStart = lib.getExe (pkgs.writeShellApplication {
          name = "install-gradient-cache-netrc";
          runtimeInputs = [pkgs.coreutils];
          text = ''
            install -m0600 \
              "$CREDENTIALS_DIRECTORY/gradient-cache-netrc" \
              /run/gradient-cache/netrc
          '';
        });
      };
    };

    security.sudo.wheelNeedsPassword = false;
    security.pam.services.swaylock = {};
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    # Copy the flake source to /etc/nixos for emergency recovery
    # In case of losing access to the main repo, any machine can rebuild itself with:
    #   cp -rL /etc/nixos /tmp/recovery && cd /tmp/recovery && nixos-rebuild switch --flake .#hostname
    environment.etc."nixos".source = inputs.self;
    environment.etc."nixos-revision".text = inputs.self.rev or inputs.self.dirtyRev or "unknown";
  };
}
