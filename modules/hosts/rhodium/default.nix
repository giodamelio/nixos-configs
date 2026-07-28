# rhodium — Raspberry Pi 4 SD-image host. Fully den-native: the shared base
# (required/deployed-apps/reverse-proxy, basic-packages, basic-settings) now
# arrives via den.default (see modules/den.nix), and the aspect bodies close
# over `inputs` from their file scope — so this host needs no `instantiate`
# specialArgs bridge and no inputs.self.nixosModules.* imports. den's default
# nixosSystem builds it.
{den, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  # Declare the host (platform comes from the attr path) with its server user.
  # The aspects named `rhodium` and `server` attach by convention; the base
  # bundle arrives via den.default.
  den.hosts.aarch64-linux.rhodium = {
    role = "server";

    # ed25519 host key (ssh-keyscan 10.30.0.12). Schema-required for an enabled
    # host, but currently unread — the only consumer, hostTargetsOf, is dead
    # since the step-ca cutover (verification is CA-name-based now). Kept for
    # fleet consistency; slated for fleet-wide removal (see MIGRATION.md). First
    # cert is minted by ca-enroll-host on strontium.
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkE6PN130cM8CjSe1NcwKfjXX7niAxiXpVzX+N5NdVH";
    # Plain system account, no Home-Manager (empty classes) — matches the
    # original inline users.users.server (which had no HM).
    users.server.classes = [];

    # Static networking rendered by the network aspect (see gallium).
    network = {
      mode = "static";
      interfaces.end0 = {
        address = "10.30.0.12";
        prefixLength = 24;
        gateway = "10.30.0.1";
      };
    };

    # Authoritative DNS replica (gallium and carbon serve the same zone).
    dns.serve.enable = true;
  };

  # Run the heartbeat collector (pushes to its own Healthchecks check).
  den.aspects.rhodium.includes = [
    den.aspects.server-heartbeat
    den.aspects.rayfish
  ];

  den.aspects.rhodium.nixos = {
    modulesPath,
    pkgs,
    lib,
    ...
  }: {
    # This host has only ever had agevault-managed secrets; keep it that way
    # rather than hand-placing the legacy hyphenated blob for Caddy's TLS.
    # TODO: drop once carbon+gallium migrate and the knob is deleted (tmp/TODO.md).
    services.gio.reverse-proxy.cloudflareCredential = "caddy_cloudflare_api_token";
    fleet.credentials.needs = ["caddy_cloudflare_api_token"];

    imports = [
      # Raw sd-image.nix leaves the firmware partition empty (no start4.elf,
      # config.txt, u-boot) — the aarch64 variant is what makes the Pi bootable.
      # Mainline kernel, no nixos-hardware: its downstream kernel + u-boot combo
      # is the breakage-prone path and nothing here needs it.
      "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

      # Hardware (was nix/hosts/rhodium/hardware.nix).
      {
        networking.hostName = "rhodium";
        sdImage.compressImage = false;
        console.enable = true;
        # Mainline kernel puts the GPIO-header mini UART on ttyS1. mkAfter so
        # our console= lands last (= /dev/console, stage-1 shell on serial)
        # after the wrong-for-Pi4 defaults sd-image-aarch64 appends.
        boot.kernelParams = lib.mkAfter [
          "earlycon=uart8250,mmio32,0xfe215040"
          "keep_bootcon"
          "loglevel=7"
          "console=ttyS1,115200n8"
        ];
        # Pi 4 USB (VL805) — nixos-hardware used to provide these
        boot.initrd.availableKernelModules = ["pcie-brcmstb" "reset-raspberrypi"];
        # Headless, ethernet-only — no Bluetooth, no WiFi. All front-ends must be
        # listed or they'd pull core modules in as dependencies despite the blacklist.
        boot.blacklistedKernelModules = [
          "hci_uart"
          "btbcm"
          "btsdio"
          "bluetooth"
          "brcmfmac"
          "brcmutil"
        ];
        # TEMPORARY: serial-console autologin for bring-up debugging; remove once deployed
        services.getty.autologinUser = "server";
        hardware.enableRedistributableFirmware = lib.mkDefault true;
        # No ZFS on this host
        boot.supportedFilesystems.zfs = lib.mkForce false;
        boot.initrd.allowMissingModules = true;
      }

      # Interface/addressing comes from the network aspect (host.network above)
      {
        networking = {
          firewall = {
            enable = true;
            allowPing = true;
          };
          nftables.enable = true;
        };
      }

      # Raspberry Pi utilities.
      {
        environment.systemPackages = with pkgs; [
          libraspberrypi
          raspberrypi-eeprom
        ];
      }
    ];

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "25.11";
  };

  # rhodium's server user, modeled as a den user entity (replaces the old inline
  # users.users.server block). define-user + user-shell provide isNormalUser,
  # home, zsh shell and programs.zsh; the `user` class carries the wheel group
  # and SSH keys (forwarded to users.users.server by the os-user battery).
  # Passwordless sudo comes from basic-settings (via den.default).
  den.aspects.server = {
    includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")
    ];
    user = {
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
  };
}
