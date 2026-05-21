{
  pkgs,
  flake,
  ...
}: let
  webhookcatcher = flake.packages.${pkgs.stdenv.hostPlatform.system}.webhookcatcher;
  configFile = (pkgs.formats.toml {}).generate "webhookcatcher.toml" {
    hook = [
      {
        id = "print-test";
        actions.print = {};
      }
    ];
  };
in {
  services.caddy.virtualHosts."https://hooks.gio.ninja:47291" = {
    extraConfig = ''
      log {
        output file /var/log/caddy/hooks.gio.ninja.log
        format json
      }

      tls {
        dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
        resolvers 1.1.1.1
      }

      reverse_proxy unix//run/webhookcatcher.sock
    '';
  };

  systemd.sockets.webhookcatcher = {
    description = "Webhook Catcher Socket";
    wantedBy = ["sockets.target"];
    socketConfig = {
      ListenStream = "/run/webhookcatcher.sock";
      SocketMode = "0666";
    };
  };

  systemd.services.webhookcatcher = {
    description = "Webhook Catcher";
    requires = ["webhookcatcher.socket"];
    after = ["webhookcatcher.socket"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${webhookcatcher}/bin/webhookcatcher ${configFile}";
      Restart = "on-failure";
      DynamicUser = true;
    };
  };

  networking.firewall.allowedTCPPorts = [47291];

  # # We define the crowdsec tables ourselves so the drop rules are scoped to
  # # port 47291 only. The bouncer's default table names ("crowdsec" / "crowdsec6")
  # # must stay separate — using the same name for both causes a Nix duplicate
  # # attribute error in the bouncer module regardless of createRulesets.
  # networking.nftables.tables."crowdsec" = {
  #   family = "ip";
  #   content = ''
  #     set crowdsec-blacklists {
  #       type ipv4_addr
  #       flags dynamic, timeout
  #     }
  #
  #     chain hook-input {
  #       type filter hook input priority -1
  #       ip saddr @crowdsec-blacklists tcp dport 47291 counter drop
  #     }
  #   '';
  # };
  #
  # networking.nftables.tables."crowdsec6" = {
  #   family = "ip6";
  #   content = ''
  #     set crowdsec6-blacklists {
  #       type ipv6_addr
  #       flags dynamic, timeout
  #     }
  #
  #     chain hook-input {
  #       type filter hook input priority -1
  #       ip6 saddr @crowdsec6-blacklists tcp dport 47291 counter drop
  #     }
  #   '';
  # };
  #
  # services.crowdsec = {
  #   enable = true;
  #   hub.collections = ["crowdsecurity/caddy"];
  #   localConfig.acquisitions = [
  #     {
  #       source = "file";
  #       filenames = ["/var/log/caddy/hooks.gio.ninja.log"];
  #       labels = {
  #         type = "caddy";
  #       };
  #     }
  #   ];
  # };
  #
  # services.crowdsec-firewall-bouncer = {
  #   enable = true;
  #   registerBouncer.enable = true;
  #   createRulesets = lib.mkForce false;
  #   settings = {
  #     mode = "nftables";
  #     nftables = {
  #       ipv4.set-only = true;
  #       ipv6.set-only = true;
  #     };
  #   };
  # };
}
