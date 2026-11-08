# telemetry

See [docs/telemetry.md](../../../docs/telemetry.md).

Invariant: `fleet.telemetry.clusterNodes` and the service list in `schema.nix` are append-only. Tunnel ports are `21000 + peerIndex * 100 + serviceIndex`, so inserting or reordering moves every existing tunnel.
