{inputs, ...}: {
  den.aspects.gallium.nixos = {
    config,
    lib,
    ...
  }: let
    credentials = [
      "niks3_api_token"
      "niks3_sign_key"
      "niks3_s3_access_key"
      "niks3_s3_secret_key"
    ];

    secret = name: "/run/credentials/niks3.service/${name}";

    # From `ray config get net.flow-label --network nix-cache`; derived from the room id.
    nixCacheFlowLabel = "0x49589";
  in {
    imports = [inputs.niks3.nixosModules.niks3];

    services.niks3 = {
      enable = true;
      httpAddr = "127.0.0.1:5751";

      s3 = {
        endpoint = "127.0.0.1:3900";
        useSSL = false;
        # Presigned URLs are signed against this host, not the loopback endpoint.
        publicUrl = "https://s3.garage.gio.ninja";
        bucket = "nix-cache";
        region = "garage";
        # garage's root_domain doesn't cover the loopback endpoint.
        bucketLookup = "path";
        accessKeyFile = secret "niks3_s3_access_key";
        secretKeyFile = secret "niks3_s3_secret_key";
      };

      apiTokenFile = secret "niks3_api_token";
      signKeyFiles = [(secret "niks3_sign_key")];

      readProxy = {
        enable = true;
        redirectTTL = "15m";
      };

      cacheUrl = "https://cache.gio.ninja";
      serverUrl = "https://cache.gio.ninja";

      oidc.providers.github = {
        issuer = "https://token.actions.githubusercontent.com";
        audience = "https://cache.gio.ninja";
        boundClaims = {
          repository_owner = ["giodamelio"];
          ref = ["refs/heads/main"];
        };
        scopes = ["write"];
      };
    };

    # Mesh-only copy of the cache and S3 vhosts for nix-cache rayfish peers.
    # Nothing else listens here, so a spoofed Host header can't reach other vhosts.
    services.caddy.virtualHosts = lib.genAttrs ["https://cache.gio.ninja:8443" "https://s3.garage.gio.ninja:8443"] (addr: {
      extraConfig = ''
        tls {
          dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
          resolvers 1.1.1.1
        }
        reverse_proxy ${
          if lib.hasPrefix "https://cache." addr
          then config.services.niks3.httpAddr
          else "127.0.0.1:3900"
        }
      '';
    });

    networking.firewall.interfaces.rayfish0.allowedTCPPorts = [8443];

    # The forked rayfish stamps this flow label on every packet arriving over the
    # nix-cache network, so only those peers get steered to the :8443 copy.
    networking.nftables.tables.nix-cache-redirect = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat;
          iifname "rayfish0" ip6 flowlabel ${nixCacheFlowLabel} tcp dport 443 redirect to :8443
        }
      '';
    };

    fleet.credentials.needs = credentials;

    systemd.services.niks3.serviceConfig.LoadCredentialEncrypted = credentials;

    # A sandboxed unit only ever sees its OWN credentials directory — systemd
    # binds that one in and mounts the rest of /run/credentials inaccessible
    # (namespace.c). So gc gets its own copy of the token and reads it from %d
    # rather than from niks3.service's path, which the module bakes in.
    systemd.services.niks3-gc.serviceConfig = {
      LoadCredentialEncrypted = ["niks3_api_token"];
      ExecStart = lib.mkForce ''
        ${lib.getExe' config.services.niks3.package "niks3"} gc \
          --server-url "http://${config.services.niks3.httpAddr}" \
          --auth-token-path "%d/niks3_api_token" \
          --older-than "${config.services.niks3.gc.olderThan}" \
          --failed-uploads-older-than "${config.services.niks3.gc.failedUploadsOlderThan}"
      '';
    };

    environment.systemPackages = [config.services.niks3.package];
  };

  den.hosts.x86_64-linux.gallium.services.niks3 = {
    endpoint = {
      domain = "cache";
      backend.host = "localhost";
      backend.port = 5751;
    };
    healthcheck.target = "https://cache.gio.ninja/health";
  };
}
