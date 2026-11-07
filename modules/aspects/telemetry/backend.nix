_: {
  den.aspects.telemetry-backend.nixos = {
    host,
    fleet,
    lib,
    perSystem,
    ...
  }: let
    cfg = fleet.telemetry;
    isMember = lib.elem host.name cfg.clusterNodes;
    peers = lib.filter (n: n != host.name) cfg.clusterNodes;
    ports = cfg.services;
    tunnel = peer: service: cfg.tunnelPorts.${peer}.${service};

    loopback = "127.0.0.1";
    vm = perSystem.giopkgs.victoriametrics-cluster;
    vl = perSystem.giopkgs.victorialogs-vlagent;

    # Dedup is 1ms because it only needs to collapse identical replicas
    # (replication factor 2) and retried batches. No vmalert recording rules are
    # used. vmalert runs on every cluster member; if recording rules are ever
    # added, each member writes them at slightly different times. In that case
    # either raise `-dedup.minScrapeInterval` on vmselect and vmstorage to the rule
    # evaluation interval (and keep scrape intervals at or above it), or run
    # recording rules on a single member.
    dedup = "-dedup.minScrapeInterval=1ms";

    # Keep at 2 when more members are added.
    replication = "-replicationFactor=2";

    storageNodes = service: local:
      map (addr: "-storageNode=${addr}") (
        ["${loopback}:${toString local}"]
        ++ map (peer: "${loopback}:${toString (tunnel peer service)}") peers
      );

    hardening = {
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 2;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RemoveIPC = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      # mincore is outside @system-service but the storage engines mmap their data.
      SystemCallFilter = ["@system-service" "~@privileged" "mincore"];
    };

    unit = description: serviceConfig: extra:
      {
        inherit description;
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = hardening // serviceConfig;
      }
      // extra;
  in
    lib.mkIf isMember {
      assertions = [
        {
          assertion = lib.length cfg.clusterNodes >= 2;
          message = "fleet.telemetry.clusterNodes needs at least two members for replicationFactor=2.";
        }
      ];

      systemd.services = {
        vmstorage = unit "VictoriaMetrics cluster storage" {
          StateDirectory = "vmstorage";
          ExecStart = lib.escapeShellArgs [
            "${vm}/bin/vmstorage"
            "-storageDataPath=/var/lib/vmstorage"
            "-retentionPeriod=${cfg.retention.metrics}"
            "-httpListenAddr=${loopback}:8482"
            "-vminsertAddr=${loopback}:${toString ports.vmstorage-insert}"
            "-vmselectAddr=${loopback}:${toString ports.vmstorage-select}"
            dedup
          ];
        } {};

        vminsert = unit "VictoriaMetrics cluster insert" {
          ExecStart = lib.escapeShellArgs (
            ["${vm}/bin/vminsert" "-httpListenAddr=${loopback}:${toString ports.vminsert}" replication]
            ++ storageNodes "vmstorage-insert" ports.vmstorage-insert
          );
        } {wants = ["vmstorage.service"];};

        vmselect = unit "VictoriaMetrics cluster select" {
          CacheDirectory = "vmselect";
          ExecStart = lib.escapeShellArgs (
            [
              "${vm}/bin/vmselect"
              "-httpListenAddr=${loopback}:${toString ports.vmselect}"
              "-cacheDataPath=/var/cache/vmselect"
              replication
              dedup
            ]
            ++ storageNodes "vmstorage-select" ports.vmstorage-select
          );
        } {wants = ["vmstorage.service"];};

        # The disk buffer holds undelivered logs across restarts, so it lives in
        # state rather than the cache the nixpkgs module provides.
        vlagent.serviceConfig = hardening // {StateDirectory = "vlagent";};
      };

      services.victorialogs = {
        enable = true;
        package = vl;
        listenAddress = "${loopback}:${toString ports.victorialogs}";
        extraOptions = ["-retentionPeriod=${cfg.retention.logs}"];
      };

      services.vlagent = {
        enable = true;
        # The module runs lib.getExe, and this package's mainProgram is victoria-logs.
        package = vl.overrideAttrs (old: {meta = old.meta // {mainProgram = "vlagent";};});
        remoteWrite.maxDiskUsagePerUrl = "2GB";
        extraArgs =
          [
            "-httpListenAddr=${loopback}:${toString ports.vlagent}"
            "-remoteWrite.tmpDataPath=/var/lib/vlagent"
            "-remoteWrite.url=http://${loopback}:${toString ports.victorialogs}/insert/native"
          ]
          ++ map (peer: "-remoteWrite.url=http://${loopback}:${toString (tunnel peer "victorialogs")}/insert/native") peers;
      };
    };
}
