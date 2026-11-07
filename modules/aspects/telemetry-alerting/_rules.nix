let
  excludedFstypes = "tmpfs|ramfs|overlay|squashfs|nsfs|efivarfs|devtmpfs|autofs|fuse.*";
in {
  metrics.groups = [
    {
      name = "watchdog";
      rules = [
        {
          alert = "Watchdog";
          expr = "vector(1)";
          labels.severity = "none";
          annotations.summary = "Always firing; the alerting pipeline is alive while this reaches the dead-man's switch";
        }
      ];
    }
    {
      name = "hosts";
      rules = [
        {
          alert = "TargetDown";
          expr = "up == 0";
          "for" = "5m";
          labels.severity = "critical";
          annotations.summary = ''{{ $labels.job }} on {{ $labels.host }} is not scrapable'';
        }
        {
          # A dead agent stops writing `up` entirely, so `up == 0` never fires for it.
          # The 1d lookback forgets hosts that were removed on purpose.
          alert = "HostSilent";
          expr = ''
            count by (host) (last_over_time(up[1d]))
              unless
            count by (host) (last_over_time(up[5m]))
          '';
          labels.severity = "critical";
          annotations.summary = ''{{ $labels.host }} has sent no metrics for 5 minutes'';
        }
        {
          alert = "MemoryHigh";
          expr = "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9";
          "for" = "10m";
          labels.severity = "warning";
          annotations.summary = ''{{ $labels.host }} memory usage is above 90%'';
        }
        {
          alert = "FilesystemSpaceLow";
          expr = ''
            node_filesystem_avail_bytes{fstype!~"${excludedFstypes}"}
              / node_filesystem_size_bytes{fstype!~"${excludedFstypes}"} < 0.1
          '';
          "for" = "15m";
          labels.severity = "warning";
          annotations.summary = ''{{ $labels.host }}:{{ $labels.mountpoint }} has less than 10% free'';
        }
        {
          alert = "ZfsPoolUnhealthy";
          expr = "zfs_pool_health > 0";
          "for" = "5m";
          labels.severity = "critical";
          annotations.summary = ''ZFS pool {{ $labels.pool }} on {{ $labels.host }} is not ONLINE (health code {{ $value }})'';
        }
      ];
    }
    {
      name = "ingestion";
      rules = [
        {
          alert = "VictoriaMetricsRequestErrors";
          expr = ''increase(vm_http_request_errors_total{path!="/target_response"}[5m]) > 0'';
          "for" = "15m";
          labels.severity = "warning";
          annotations.summary = ''{{ $labels.job }} on {{ $labels.host }} is returning errors on {{ $labels.path }}'';
        }
        {
          alert = "VictoriaMetricsRpcErrors";
          expr = ''sum by (host, job) (increase({__name__=~"vm_rpc_(connection|dial|handshake)_errors_total"}[5m])) > 0'';
          "for" = "15m";
          labels.severity = "warning";
          annotations.summary = ''{{ $labels.job }} on {{ $labels.host }} has cluster RPC errors'';
        }
        {
          alert = "VictoriaMetricsRowsIgnored";
          expr = "sum by (host, job, reason) (increase(vm_rows_ignored_total[10m])) > 0";
          "for" = "10m";
          labels.severity = "warning";
          annotations.summary = ''{{ $labels.job }} on {{ $labels.host }} is dropping samples ({{ $labels.reason }})'';
        }
        {
          alert = "VlagentDroppingData";
          expr = "sum by (host) (increase(vlagent_remotewrite_packets_dropped_total[5m])) > 0";
          "for" = "15m";
          labels.severity = "critical";
          annotations.summary = ''vlagent on {{ $labels.host }} is dropping log data'';
        }
        {
          alert = "VlagentRemoteWriteErrors";
          expr = "sum by (host) (rate(vlagent_remotewrite_retries_count_total[5m])) > 0";
          "for" = "15m";
          labels.severity = "warning";
          annotations.summary = ''vlagent on {{ $labels.host }} keeps retrying remote writes'';
        }
        {
          alert = "VlagentBufferGrowing";
          expr = ''
            (
              deriv(vlagent_remotewrite_pending_data_bytes[30m]) > 0
                and
              vlagent_remotewrite_pending_data_bytes > 10 * 1024 * 1024
            )
          '';
          "for" = "15m";
          labels.severity = "warning";
          annotations.summary = ''vlagent buffer for {{ $labels.url }} on {{ $labels.host }} is growing'';
        }
      ];
    }
  ];

  logs.groups = [];
}
