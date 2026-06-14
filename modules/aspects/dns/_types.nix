{lib}: rec {
  # Hosts that declare a static IP -> { <host>.A = [ip]; } subzone fragment, so
  # <host>.<zone> resolves directly.
  hostARecords = denHosts:
    lib.pipe denHosts [
      (lib.filterAttrs (_name: host: (host.dns.ip or null) != null))
      (lib.mapAttrs (_name: host: {A = [host.dns.ip];}))
    ];
}
