{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./disko.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.monitoring

    # Create server user
    ({pkgs, ...}: {
      users.users.server = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      security.sudo.wheelNeedsPassword = false;
      programs.zsh.enable = true;
    })

    # Setup Pocket ID
    ({pkgs, ...}: {
      services.pocket-id = {
        enable = true;

        settings = {
          APP_URL = "https://login.gio.ninja";
          TRUST_PROXY = true;
          ENCRYPTION_KEY_FILE = "\${CREDENTIALS_DIRECTORY}/pocket-id-encryption-key";
          ANALYTICS_DISABLED = true;
        };
      };

      # Load the encrypted encryption key
      systemd.services.pocket-id.serviceConfig = {
        LoadCredentialEncrypted = "pocket-id-encryption-key:/var/lib/credstore/pocket-id-encryption-key";
      };

      # Setup Caddy as a reverse proxy
      networking.firewall.allowedTCPPorts = [80 443];
      services.caddy = {
        enable = true;

        virtualHosts."https://login.gio.ninja" = {
          extraConfig = ''
            reverse_proxy localhost:1411
          '';
        };

        virtualHosts."https://headscale.gio.ninja" = {
          extraConfig = ''
            reverse_proxy localhost:8080
          '';
        };
      };
    })

    # Run Headscale for easy networking
    {
      networking.firewall.allowedTCPPorts = [80 443];

      services.headscale = {
        enable = true;
        port = 8080;

        settings = {
          server_url = "https://headscale.gio.ninja";

          tls_cert_path = null;
          tls_key_paht = null;

          dns = {
            magic_dns = true;
            base_domain = "h.gio.ninja";
            nameservers.global = ["8.8.8.8" "8.8.4.4"];
          };

          oidc = {
            only_start_if_oidc_is_available = true;
            issuer = "https://login.gio.ninja";
            client_id = "251934f5-6b41-4665-9a7f-c475ca534c92";
            client_secret_path = "\${CREDENTIALS_DIRECTORY}/headscale-oidc-client-secret";
            scope = ["openid" "profile" "email" "groups"];
            allowed_groups = ["headscale"];
            pkce = {
              enabled = true;
              method = "S256";
            };
          };
        };
      };

      # Load the encrypted encryption key
      systemd.services.headscale.serviceConfig = {
        LoadCredentialEncrypted = "headscale-oidc-client-secret:/var/lib/credstore/headscale-oidc-client-secret";
      };
    }

    # Enable Tailscale
    {
      services.tailscale = {
        enable = true;
      };
    }
  ];

  system.stateVersion = "25.05";
}
