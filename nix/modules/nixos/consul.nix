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
  services.consul = {
    enable = true;
    extraConfigFiles = [
      config.gio.credentials.services.consul.credentialPath."consul-encrypt.json"
    ];
    extraConfig = {
      bootstrap_expect = 2;
      server = true;
      enable_syslog = true;
      retry_join = joinAddresses;
      addresses = {
        dns = "0.0.0.0";
      };
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
}
