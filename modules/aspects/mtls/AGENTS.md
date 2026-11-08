# gio.mtls

See [docs/telemetry.md](../../../docs/telemetry.md).

Invariant: `modules/hosts/strontium/app-x509.tpl` reads identity only from `.Token.*`, never `.Insecure.*`. A host controls `.Insecure.*`, so reading it lets the host choose its own role.
