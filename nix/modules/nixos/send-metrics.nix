{
  services.alloy = {
    enable = true;
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.write "loki" {
      endpoint {
        url = "https://loki.gio.ninja/loki/api/v1/push"
      }
    }

    loki.source.journal "journald" {
      forward_to    = [loki.write.loki.receiver]
      relabel_rules = loki.relabel.journal.rules
    }

    loki.relabel "journal" {
      forward_to = []

        rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
        }

        rule {
            source_labels = ["__journal__hostname"]
            target_label  = "hostname"
        }

        rule {
            source_labels = ["__journal__priority_keyword"]
            target_label  = "level"
        }

        rule {
            source_labels = ["__journal__transport"]
            target_label  = "transport"
        }

        rule {
            source_labels = ["__journal__comm"]
            target_label  = "command"
        }
    }
  '';

  # Export OS Stats
  services.prometheus = {
    exporters.node = {
      enable = true;
      port = 9000;
      enabledCollectors = [
        "systemd"
      ];
    };

    exporters.zfs = {
      enable = true;
    };
  };
}
