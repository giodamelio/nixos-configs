{
  lib,
  config,
  ...
}: let
  net = import ../network/_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  consulHosts = lib.filterAttrs (_n: h: h.consul.enable) denHosts;
  serverHosts = lib.filterAttrs (_n: h: h.consul.enable && h.consul.server) denHosts;
in {
  # Consul cluster membership. Self-gates on host.consul.enable. retry_join and
  # bind interface derive from host.network (replaces homelab.toml join addresses
  # + the hardcoded interface.bind); the gossip key is agevault's
  # consul_encrypt. Service registrations are layered on by the
  # services-consul renderer.
  den.aspects.consul.nixos = {
    host,
    config,
    lib,
    pkgs,
    ...
  }: let
    others = lib.attrNames (lib.filterAttrs (n: _: n != host.name) consulHosts);
    retryJoin = map (n: net.theAddress denHosts.${n}) others;
  in
    lib.mkIf host.consul.enable {
      services.consul = {
        enable = true;
        webUi = host.consul.webUi;
        interface.bind = net.theInterface host;
        extraConfigFiles = ["/etc/consul-encrypt.json" "/etc/consul-acl-tokens.json"];
        extraConfig = {
          server = host.consul.server;
          bootstrap_expect = lib.length (lib.attrNames serverHosts);
          retry_join = retryJoin;
          enable_syslog = true;
          addresses.dns = "0.0.0.0";
          telemetry.prometheus_retention_time = "5m";
          acl = {
            enabled = true;
            default_policy = "deny";
          };
        };
      };

      # consul_acl_tokens holds this host's token as both acl.tokens.agent and
      # acl.tokens.config_file_service_registration.
      fleet.credentials.needs = ["consul_encrypt" "consul_acl_tokens"];
      systemd.services.consul.serviceConfig.LoadCredentialEncrypted = ["consul_encrypt" "consul_acl_tokens"];
      # consul picks the config format from the file extension, and agevault
      # names cannot hold a dot, so give the credentials .json names. They resolve
      # only inside consul.service, where the credentials are mounted.
      environment.etc."consul-encrypt.json".source = "/run/credentials/consul.service/consul_encrypt";
      environment.etc."consul-acl-tokens.json".source = "/run/credentials/consul.service/consul_acl_tokens";

      # consul.service is Type=simple, so it counts as started before the agent can resolve
      # ACL tokens. Order after this instead; partOf re-runs it whenever consul restarts.
      systemd.services.consul-ready = {
        description = "Wait for the Consul agent to see a cluster leader";
        requires = ["consul.service"];
        after = ["consul.service"];
        partOf = ["consul.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          DynamicUser = true;
          TimeoutStartSec = "2min";
          ExecStart = lib.getExe (pkgs.writeShellApplication {
            name = "consul-ready";
            runtimeInputs = [pkgs.curl];
            text = ''
              until leader=$(curl -sf http://127.0.0.1:8500/v1/status/leader) && [ "$leader" != '""' ]; do
                sleep 1
              done
            '';
          });
        };
      };

      # https://developer.hashicorp.com/consul/docs/reference/architecture/ports
      # Without TLS or ACLs nothing authenticates server RPC (8300) — the gossip
      # key covers only 8301 — so only cluster peers may reach either. DNS (8600)
      # stays closed: its only consumer is the local DNS server's forward.
      assertions = [
        {
          assertion = config.networking.nftables.enable;
          message = "consul: the peer allowlist uses extraInputRules, which needs networking.nftables.enable";
        }
      ];
      networking.firewall.extraInputRules = lib.mkIf (retryJoin != []) ''
        ip saddr { ${lib.concatStringsSep ", " retryJoin} } tcp dport { 8300, 8301 } accept
        ip saddr { ${lib.concatStringsSep ", " retryJoin} } udp dport 8301 accept
      '';
    };
}
