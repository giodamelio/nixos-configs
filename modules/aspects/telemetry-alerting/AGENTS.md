# telemetry-alerting

See [docs/telemetry.md](../../../docs/telemetry.md).

Invariant: the vmalert and Alertmanager configuration stays identical on every member, with no member-specific labels. Alertmanager only deduplicates identical alerts, so a per-member label sends every notification once per member.
