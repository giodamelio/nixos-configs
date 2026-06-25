{lib, ...}: let
  l = import ./_lib.nix {inherit lib;};

  # --- pure test fixtures for _lib ---
  hc = protocol: target: {
    inherit protocol target;
    interval = "60s";
    method = "GET";
  };
  ep = attrs:
    {
      domain = "svc";
      port = 443;
      tls = true;
      proxy = true;
      extraConfig = "";
      backend = {
        host = null;
        port = null;
        socket = null;
        protocol = "http";
      };
    }
    // attrs;
  consul = attrs:
    {
      enable = true;
      name = "svc";
      address = null;
      port = null;
      tags = [];
      meta = {};
    }
    // attrs;
  svc = attrs: {
    consul = consul (attrs.consul or {});
    endpoints = attrs.endpoints or {};
    healthchecks = attrs.healthchecks or {};
  };
  # a flattened prometheus-endpoint entry (as facetEntries produces)
  pe = attrs:
    {
      host = "h";
      service = "s";
      key = "default";
      target = "localhost:9090";
      scheme = "http";
      path = "/metrics";
      job = "s";
      labels = {};
      params = {};
      auth = null;
    }
    // attrs;
  # a flattened dashboard entry
  di = attrs:
    {
      host = "h";
      service = "s";
      key = "default";
      category = "Services";
      title = "S";
      subtitle = null;
      logo = null;
      url = "https://s";
    }
    // attrs;
  t = expr: expected: {inherit expr expected;};
in {
  flake.tests.fleet-services = {
    # healthcheck -> consul check
    check-https = t (l.healthcheckToCheck (hc "https" "https://x/h")) {
      http = "https://x/h";
      interval = "60s";
      method = "GET";
    };
    check-tcp = t (l.healthcheckToCheck (hc "tcp" "10.0.0.1:445")) {
      tcp = "10.0.0.1:445";
      interval = "60s";
    };
    check-icmp-null = t (l.healthcheckToCheck (hc "icmp" "host")) null;

    # consul registration: address/port derived from the primary endpoint
    reg-derived =
      t (l.consulRegistration "gio.ninja" (svc {
        consul.name = "forgejo";
        endpoints.default = ep {domain = "forgejo";};
        healthchecks.default = hc "https" "https://forgejo.gio.ninja/v";
      })) {
        name = "forgejo";
        tags = [];
        meta = {};
        address = "forgejo.gio.ninja";
        port = 443;
        checks = [
          {
            http = "https://forgejo.gio.ninja/v";
            interval = "60s";
            method = "GET";
          }
        ];
      };
    # explicit address/port + tcp check, no endpoint
    reg-explicit =
      t (l.consulRegistration "gio.ninja" (svc {
        consul = {
          name = "samba";
          address = "10.30.0.11";
          port = 445;
        };
        healthchecks.default = hc "tcp" "10.30.0.11:445";
      })) {
        name = "samba";
        tags = [];
        meta = {};
        address = "10.30.0.11";
        port = 445;
        checks = [
          {
            tcp = "10.30.0.11:445";
            interval = "60s";
          }
        ];
      };
    # no healthcheck -> no checks key
    reg-no-checks = t ((l.consulRegistration "gio.ninja" (svc {consul.name = "x";})) ? checks) false;
    # disabled -> null
    reg-disabled = t (l.consulRegistration "gio.ninja" (svc {consul.enable = false;})) null;

    # endpointServes
    serves-proxy = t (l.endpointServes (ep {})) true;
    serves-dns-only =
      t (l.endpointServes (ep {
        proxy = false;
        backend.port = null;
      }))
      false;
    serves-custom =
      t (l.endpointServes (ep {
        proxy = false;
        extraConfig = "file_server";
      }))
      true;

    # endpoint -> vhost: public vs backend port disambiguation + tls passthrough
    vhost-ports = t (let
      v = l.endpointToVHost (ep {
        port = 8443;
        tls = false;
        backend.host = "localhost";
        backend.port = 9100;
      });
    in {inherit (v) listenPort port host tls;}) {
      listenPort = 8443;
      port = 9100;
      host = "localhost";
      tls = false;
    };

    # fleet-wide domain uniqueness (drives the build-blocking assertion)
    dup-domains = t (l.duplicateDomains [{domain = "a";} {domain = "b";} {domain = "a";}]) ["a"];
    dup-none = t (l.duplicateDomains [{domain = "a";} {domain = "b";}]) [];

    # prometheus scrape_config from facet entries
    scrape-basic = t (l.scrapeConfigOf "node" [(pe {target = "localhost:9000";})]) {
      job_name = "node";
      static_configs = [{targets = ["localhost:9000"];}];
    };
    scrape-multi-host =
      t
      (l.scrapeConfigOf "node" [
        (pe {
          target = "localhost:9000";
          labels.host = "carbon";
        })
        (pe {
          target = "gallium.gio.ninja:9000";
          labels.host = "gallium";
        })
      ]).static_configs [
        {
          targets = ["localhost:9000"];
          labels.host = "carbon";
        }
        {
          targets = ["gallium.gio.ninja:9000"];
          labels.host = "gallium";
        }
      ];
    scrape-https-path = t (let
      c = l.scrapeConfigOf "immich_api" [
        (pe {
          scheme = "https";
          path = "/metrics/api";
        })
      ];
    in {inherit (c) metrics_path scheme;}) {
      metrics_path = "/metrics/api";
      scheme = "https";
    };
    scrape-default-omits =
      t (let
        c = l.scrapeConfigOf "x" [(pe {})];
      in {
        hasPath = c ? metrics_path;
        hasScheme = c ? scheme;
      }) {
        hasPath = false;
        hasScheme = false;
      };
    scrape-auth =
      t
      (l.scrapeConfigOf "garage" [
        (pe {
          auth = {
            credentials = null;
            credentialsFile = "/run/x";
          };
        })
      ]).authorization {
        type = "Bearer";
        credentials_file = "/run/x";
      };
    scrape-params = t (l.scrapeConfigOf "consul" [(pe {params.format = ["prometheus"];})]).params {format = ["prometheus"];};

    # homer dashboard items + groups
    homer-item-min = t (l.dashboardToItem (di {})) {
      name = "S";
      url = "https://s";
    };
    homer-item-full =
      t (l.dashboardToItem (di {
        subtitle = "sub";
        logo = "l";
      })) {
        name = "S";
        url = "https://s";
        subtitle = "sub";
        logo = "l";
      };
    homer-group = t (l.homerGroupOf "Media" [(di {title = "A";}) (di {title = "B";})]) {
      name = "Media";
      items = [
        {
          name = "A";
          url = "https://s";
        }
        {
          name = "B";
          url = "https://s";
        }
      ];
    };
  };
}
