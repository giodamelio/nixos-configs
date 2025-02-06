_: {
  pkgs,
  config,
  ...
}: let
  baseDomain = "netbird.gio.ninja";
in {
  # Load our secrets
  age.secrets.cert_netbird_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;

  environment.systemPackages = [
    # (pkgs.stdenv.mkDerivation rec {
    #   pname = "netbird";
    #   version = "0.22.6";
    #   src = pkgs.fetchurl {
    #     url = "https://github.com/netbirdio/netbird/releases/download/v${version}/netbird_${version}_linux_amd64.tar.gz";
    #     sha256 = "sha256-JpVYF9z3SNZPi8SiFanW33AKJpVVUZlS4wyR51KqX8A=";
    #   };
    #
    #   installPhase = ''
    #     mkdir -p $out/bin
    #     cp netbird $out/bin/
    #   '';
    #
    #   # Work around the "unpacker appears to have produced no directories"
    #   setSourceRoot = "sourceRoot=`pwd`";
    # })
    # (pkgs.buildGoModule rec {
    #   pname = "netbird";
    #   version = "0.22.6";
    #
    #   src = pkgs.fetchFromGitHub {
    #     owner = "netbirdio";
    #     repo = "netbird";
    #     rev = "v${version}";
    #     hash = "sha256-/7iJbl9MFe5D9g+4a8nFavZG3jXIiEgKU3toGpx0hyM=";
    #   };
    #
    #   vendorHash = "sha256-CwozOBAPFSsa1XzDOHBgmFSwGiNekWT8t7KGR2KOOX4=";
    #   subPackages = ["management" "signal"];
    #
    #   ldflags = [ "-X=github.com/netbirdio/netbird/version.version=${version}" ];
    # })
  ];

  # Get HTTPS certificates from LetsEncrypt
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."netbird.gio.ninja" = {
      dnsProvider = "cloudflare";
      domain = baseDomain;
      credentialsFile = config.age.secrets.cert_netbird_gio_ninja.path;
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

    globalConfig = ''
      servers {
        protocols h1 h2 h2c
      }
    '';

    virtualHosts."https://netbird.gio.ninja" = {
      useACMEHost = "netbird.gio.ninja";
      extraConfig = ''
        route / {
          root * ${n.netmaker-ui}
          file_server
        }
        # route /signalexchange.SignalExchange/ {
        #   reverse_proxy h2c://localhost:9010
        # }
      '';
    };
  };

  # Netbird Signal Server
  systemd.services.netbird-signal = {
    description = "Netbird Signal service";

    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.netbird}/bin/netbird-signal run --port 9010 --log-file console --log-level debug";
      DynamicUser = true;
      User = "netbird";
      Group = "netbird";
    };
  };

  # Config our TURN server
  services.coturn = {
    enable = true;
  };

  # Open up firewall ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      # Caddy Proxy
      80
      443
    ];
    allowedUDPPorts = [
      # Turnserver
      3478
    ];
    allowedUDPPortRanges = [
      # Turnserver
      {
        from = 49152;
        to = 65535;
      }
    ];
  };
}
