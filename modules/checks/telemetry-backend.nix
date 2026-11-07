_: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # The driver numbers vlan addresses by sorted node name (tela, telb).
    addressOf = {
      tel-a = "192.168.1.1";
      tel-b = "192.168.1.2";
    };
    tunnelled = ["vmstorage-insert" "vmstorage-select" "victorialogs"];
  in {
    denTests.telemetry-backend = {
      fleet = {den, ...}: {
        den.hosts.x86_64-linux = lib.genAttrs ["tel-a" "tel-b"] (_: {ssh.hostKey = null;});
        fleet.telemetry.clusterNodes = ["tel-a" "tel-b"];

        # Plain TCP stand-in for the caddy-l4 tunnels, wired from the same port
        # table: a listener on the member's address per service, and a loopback
        # tunnel port per peer service.
        den.aspects.tel-tunnels.nixos = {
          host,
          fleet,
          ...
        }: let
          peers = lib.filter (n: n != host.name) fleet.telemetry.clusterNodes;
          socat = listen: target: {
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${listen},fork,reuseaddr TCP:${target}";
              Restart = "always";
              RestartSec = 1;
            };
          };
        in {
          system.stateVersion = "25.11";
          networking.firewall.allowedTCPPorts = map (s: fleet.telemetry.services.${s}) tunnelled;
          systemd.services =
            lib.listToAttrs (map (s: let
              port = toString fleet.telemetry.services.${s};
            in
              lib.nameValuePair "serve-${s}" (socat "${port},bind=${addressOf.${host.name}}" "127.0.0.1:${port}"))
            tunnelled)
            // lib.listToAttrs (lib.concatMap (peer:
              map (s:
                lib.nameValuePair "tunnel-${peer}-${s}" (socat "${toString fleet.telemetry.tunnelPorts.${peer}.${s}},bind=127.0.0.1" "${peer}:${toString fleet.telemetry.services.${s}}"))
              tunnelled)
            peers);
        };

        den.aspects.tel-a.includes = [den.aspects.telemetry-backend den.aspects.tel-tunnels];
        den.aspects.tel-b.includes = [den.aspects.telemetry-backend den.aspects.tel-tunnels];
      };

      nodes = {
        tela = "tel-a";
        telb = "tel-b";
      };

      node = _: {
        nodes,
        lib,
        ...
      }: {
        networking.extraHosts = lib.mkAfter ''
          ${nodes.tela.networking.primaryIPAddress} tel-a
          ${nodes.telb.networking.primaryIPAddress} tel-b
        '';
      };

      testScript = ''
        units = ["vmstorage", "vminsert", "vmselect", "victorialogs", "vlagent"]
        start_all()
        for m, addr in ((tela, "${addressOf.tel-a}"), (telb, "${addressOf.tel-b}")):
            m.wait_for_unit("multi-user.target")
            assert f"{addr}/" in m.succeed("ip -4 -o addr show eth1"), f"{m.name} is not {addr}"
            for u in units:
                m.wait_for_unit(f"{u}.service")
            for port in (8400, 8401, 8480, 8481, 8482, 9428, 9429):
                m.wait_for_open_port(port, "127.0.0.1")

        with subtest("services listen on loopback only"):
            for m in (tela, telb):
                listening = m.succeed("ss -tlnH")
                for port in (8480, 8481, 8482, 9428, 9429):
                    assert f"127.0.0.1:{port}" in listening, f"{port} not on loopback"
                    assert f"0.0.0.0:{port}" not in listening and f"*:{port}" not in listening

        with subtest("a write to vminsert is queryable from the same node's vmselect"):
            tela.succeed("curl -sf -d 'spike_metric{src=\"a\"} 42' http://127.0.0.1:8480/insert/0/prometheus/api/v1/import/prometheus")
            tela.wait_until_succeeds("curl -sf 'http://127.0.0.1:8481/select/0/prometheus/api/v1/query?query=spike_metric' | grep -q '\"42\"'")

        with subtest("replication factor 2: the other member answers the same query"):
            telb.wait_until_succeeds("curl -sf 'http://127.0.0.1:8481/select/0/prometheus/api/v1/query?query=spike_metric' | grep -q '\"42\"'")

        with subtest("the data survives losing the local vmstorage"):
            tela.succeed("systemctl stop vmstorage.service")
            tela.wait_until_succeeds("curl -sf 'http://127.0.0.1:8481/select/0/prometheus/api/v1/query?query=spike_metric' | grep -q '\"42\"'")
            tela.succeed("systemctl start vmstorage.service")

        with subtest("journald entries posted to vlagent land in both VictoriaLogs"):
            tela.succeed(
                "printf '__REALTIME_TIMESTAMP=%s\\n_HOSTNAME=spikehost\\n_SYSTEMD_UNIT=spike.service\\nCUSTOM=keep\\nMESSAGE=hello journald\\n\\n' \"$(date +%s)000000\""
                " | curl -sf -X POST -H 'Content-Type: application/vnd.fdo.journal' --data-binary @- http://127.0.0.1:9429/insert/journald/upload"
            )
            for m in (tela, telb):
                m.wait_until_succeeds("curl -sf http://127.0.0.1:9428/select/logsql/query -d 'query=_HOSTNAME:spikehost' | grep -q '\"CUSTOM\":\"keep\"'")
      '';
    };
  };
}
