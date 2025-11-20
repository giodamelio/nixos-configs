{
  pkgs,
  config,
  ...
}: let
  inherit (pkgs) lib;

  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);

  # Get all the join addresses from our config
  joinAddresses = lib.pipe homelab.machines [
    builtins.attrValues
    (builtins.map (
      machine:
        lib.attrsets.attrByPath ["consul" "join_address"] null machine
    ))
    (builtins.filter (addr: addr != null))
    # Remove self from the list
    (builtins.filter (
      addr:
        !(lib.hasPrefix config.networking.hostName addr)
    ))
  ];
in {
  options.gio.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.consul = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Consul service definition for this service";
      };
    });
    default = {};
    description = "Service definitions with Consul integration";
  };

  config = {
    services.consul = {
      enable = true;
      extraConfigFiles =
        [
          config.gio.credentials.services.consul.credentialPath."consul-encrypt.json"
        ]
        ++ lib.optional (builtins.length (builtins.attrValues config.gio.services) > 0) "/etc/consul.d/services.json";
      extraConfig = {
        bootstrap_expect = 2;
        server = true;
        enable_syslog = true;
        retry_join = joinAddresses;
        addresses = {
          dns = "0.0.0.0";
        };
        telemetry = {
          prometheus_retention_time = "5m";
        };
      };
    };

    # Generate Consul service definitions
    environment.etc = let
      serviceDefinitions = lib.pipe config.gio.services [
        builtins.attrValues
        (builtins.filter (svc: svc.consul != null))
        (builtins.map (svc: svc.consul))
      ];
    in
      lib.mkIf (builtins.length serviceDefinitions > 0) {
        "consul.d/services.json".text = builtins.toJSON {
          services = serviceDefinitions;
        };
      };

    # See: https://developer.hashicorp.com/consul/docs/reference/architecture/ports
    networking.firewall.allowedTCPPorts = [
      8300 # Server RPC
      8301 # LAN serf
      8600 # DNS server
    ];
    networking.firewall.allowedUDPPorts = [
      8301 # LAN serf
      8600 # DNS server
    ];

    gio.credentials = {
      enable = true;
      services = {
        "consul" = {
          loadCredentialEncrypted = ["consul-encrypt.json"];
        };
      };
    };
  };
}
