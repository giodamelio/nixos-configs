# Homelab telemetry stack: implementation plan

This plan replaces the current monitoring setup (central Prometheus scraping, Grafana Alloy shipping journald to Loki via the `send-metrics` aspect, and Netdata) with a push-based VictoriaMetrics + VictoriaLogs stack that survives the loss of one backend node.

Work through the phases in order. Each phase must be complete and verified before starting the next. The existing monitoring setup keeps running in parallel until Phase 4.

---

## Overview

### Hosts and roles

- **Cluster members** (initially `carbon` and `gallium`): run the VictoriaMetrics cluster, VictoriaLogs, alerting, and the Caddy front door.
- **carbon** additionally hosts all human-facing web UIs (it has much more CPU).
- **Every host except `aluminum`** (servers, Raspberry Pis, desktops and `oganesson`, including the cluster members): runs exporters, `vmagent` and `systemd-journal-upload`.
- **CoreDNS** runs on `carbon`, `gallium` and `rhodium`.

### Data flow

- **Metrics:** exporters (localhost) → `vmagent` → `https://telemetry.gio.ninja/metrics/...` (mTLS) → Caddy → `vminsert` → `vmstorage` on all members (replication factor 2).
- **Logs:** journald → `systemd-journal-upload` → `https://telemetry.gio.ninja/logs/...` (mTLS) → Caddy → `vlagent` → VictoriaLogs on all members.
- **Queries:** Grafana on carbon → carbon's local `vmselect` and VictoriaLogs.
- **Alerts:** `vmalert` on every member → Alertmanager on every member (gossip-clustered) → notifications, plus a Watchdog ping to healthchecks.io.

### Cluster member list (single source of truth)

Define one list of cluster members in den (e.g. `telemetry.clusterNodes = [ "carbon" "gallium" ]`). Everything cluster-related is derived from it:

- `vminsert` / `vmselect` storage node lists
- caddy-l4 internal listeners, peer tunnels and allowed client CNs
- Caddy front-door upstreams and peer fallbacks
- `vlagent` write targets
- Alertmanager gossip peers and `vmalert` notifier targets
- DNS A records for `telemetry.gio.ninja` and `push.telemetry.gio.ninja`
- Firewall rules for internal ports
- Membership of the CN allowlists (every `telemetry-node.<member>`)

Adding a cluster member must only require importing the module on the new host, adding it to the list, and issuing its certificates.

---

## Phase 0: DNS resolver fix

Make DNS server failover work on every host before relying on DNS-based client failover.

This is already implemented: `modules/aspects/network/static-network.nix` sets `DNS=` on every static host to every static host with `dns.serve.enable` (carbon, gallium, rhodium), via `net.dnsServerAddresses` in `modules/aspects/network/_lib.nix`. Phase 0 is verification only.

1. Hosts on DHCP already receive all three servers; leave them as is.
2. Keep systemd-resolved as the resolver on servers.

**Verify:** `resolvectl status` on each static host shows all three servers on the relevant link. Stop CoreDNS on one server and confirm name resolution still works on the others.

---

## Phase 1: Generic mTLS certificate module

A generic NixOS module for declaring and consuming service certificates from the existing step-ca system. It must know nothing about telemetry; NATS and custom applications will use it later.

### CA requirements

- Certificates are declared statically in NixOS config and issued through the existing manual one-time-secret process (same as SSH certs). Hosts never request new identities.
- A certificate's CN, URI SAN, OU and DNS SANs are fixed at initial issuance; the requesting host cannot choose or influence them.
- Renewal and rekeying preserve subject and SANs exactly; only validity dates (and key, for rekey) change.
- Changing a certificate's identity or role requires a new issuance, never a renewal.
- Certificates are short-lived and renewed automatically; revocation (refusing renewal) is the cut-off mechanism.
- Certificates must include both serverAuth and clientAuth extended key usage.

### Configure the `app` provisioner on strontium

One JWK provisioner, `app`, issues every application certificate regardless of role. Add it to `managedProvisioners` in `modules/hosts/strontium/step-ca.nix`.

- **Lifetime:** 7 days default and maximum, the same as `nfs`. A host that is off for more than 7 days needs re-enrolling. Leave `allowRenewalAfterExpiry` off, so a stolen expired certificate cannot renew.
- **Role:** the enroll token carries the role as signed template data (`step ca token ... --set role=<role>`, which step-cli puts in the token's `user` claim). The provisioner key never leaves strontium, so the host cannot change it.
- **Template:** sets `O=app` (the provisioner name), `OU={{ .Token.user.role }}`, the CN and SANs from the token, and both EKUs. It must read only `.Token.*`, never `.Insecure.*`: `.Insecure.User` is data the requesting host supplies with `step ca certificate --set`.
- **Renewal** copies the old certificate (`Authority.Renew`), so subject and SANs never change after issuance.
- **O names the provisioner:** also give the `nfs` provisioner a template that sets `O=nfs`. Existing NFS certificates pick it up on their next enrollment, not on renewal. Only the `app` template ever sets an OU, so an OU match also proves the certificate came from `app`.

Known trade-offs of a single provisioner: its key can mint any role, every app certificate shares one lifetime and name policy, and the step-ca log shows `app` as the provisioner for every role. Rotating the provisioner key is safe; existing certificates renew with themselves.

### Enroll and revoke from strontium

- `ca-enroll-host <host> mtls` is generated from den config. It mints one token per certificate the host declares, and fails on a role that no declaration uses. Before the paste block it prints the CN, role and SANs of each token, for the operator to read before pasting.
- `ca-revoke <cn>` finds the newest serial for the CN in the step-ca journal, mints a revoke token from `app`, and runs `step ca revoke`. Revoke the newest serial: every renewal issues a new serial, so revoking an older one leaves the current certificate alive. Revocation is passive; the certificate cannot renew and dies within its lifetime.
- Revocation is also published as a standard CRL (next section), so verifiers that check CRLs reject a revoked certificate within minutes instead of at expiry.
- Switch step-ca's `logger.format` from `text` to `json` so the journal is queryable with `jq`. The log already records serial, CN, SANs, validity, provisioner and the full certificate on every sign, renew, rekey and revoke.

### Identity conventions

For a certificate for application `<app>` on host `<host>`:

- **CN:** `<app>.<host>`
- **URI SAN:** `spiffe://gio.ninja/<host>/<app>`
- **OU:** the role (e.g. `telemetry-writer`)
- **DNS SANs:** only for services that also act as servers, and only for hostnames that actually resolve to that host. Pure client certificates have no DNS SANs.

Services always authorize callers by name (CN or OU), never merely by "has a valid certificate".

### Module interface

A den aspect at `modules/aspects/mtls/` exposing `gio.mtls.certs.<name>` with:

- `app`, `role` (OU), optional `serverHostnames` (DNS SANs); host taken from the host config
- `service`: the systemd unit(s) that consume the certificate
- `onRenew`: `restart`, `reload`, or `reload-caddy` (`systemctl reload caddy`)

It is built alongside `modules/aspects/nfs/cert.nix`, which stays as it is for now.

The module must:

1. Derive CN, URI SAN, OU and DNS SANs from the declaration.
2. Store certificate and key root-owned under `/var/lib/mtls/<name>/` and deliver them to consuming services with systemd `LoadCredential=` (works with `DynamicUser`). For Caddy, make the files readable by the Caddy service.
3. Use one set of units per host, not per certificate:
   - `mtls-enroll.path` watches `/var/lib/mtls/tokens/`; the strontium paste drops one token file per certificate, and the enroll service consumes and deletes each one.
   - `mtls-renew.timer` runs every 12 hours. For each declared certificate it runs the drift check, then `step ca renew --expires-in 120h` (renews once a certificate is about 2 days old, leaving about 5 days of CA outage before anything expires), then the `onRenew` action. The unit fails and names every certificate that broke.
   - Renewal authenticates with the certificate itself, so the same timer can renew certificates from any provisioner (NFS can fold into it later).
4. **Drift check:** compare the certificate on disk with the declared identity (CN, URI SAN, O, OU, DNS SANs). On mismatch, fail loudly (failed unit and log message) so the operator knows to run the manual reissue step. Never silently keep renewing a certificate that no longer matches config.
5. Expose the CA root certificate path (`/etc/step/ca-root.crt`) for services that need a trust pool.

### Publish the CRL

Use the standard mechanisms (RFC 5280), so any well-behaved verifier can check revocation, not only Caddy.

- **step-ca:** `crl: { enabled: true, generateOnRevoke: true, cacheDuration: "24h", idpURL: "http://crl.gio.ninja/" }`. `generateOnRevoke` rebuilds the CRL the moment `ca-revoke` runs.
- **Plain HTTP endpoint:** serve `http://crl.gio.ninja/` from strontium on port 80, proxying to step-ca's `https://127.0.0.1/1.0/crl` with the step-ca root. Plain HTTP is standard for CRL distribution: the CRL is signed by the CA, so the transport needs no trust, and it avoids needing TLS to check TLS. step-ca's own HTTPS endpoint is signed by the step-ca root, which is not in any system trust store, so verifiers using system trust could not fetch it. Do not add the step-ca root to system trust instead: step-ca has no name constraints, so that would let it vouch for any hostname.
- **Certificates:** the `app` template sets `"crlDistributionPoints": ["http://crl.gio.ninja/"]`. Add it before the first `app` certificate is issued: renewal copies the old certificate including its extensions, so a certificate issued without it never gains it short of re-enrollment.
- **OCSP:** step-ca has no OCSP responder. If it gains one, add an `ocspServer` URL to the template and re-enroll every host with `ca-enroll-host`. Do not add a placeholder OCSP URL before then; verifiers that try a dead responder fail or stall.
- **DNS:** add `crl.gio.ninja` → strontium to the Nix-generated zone.

### Documentation

Add a short README for the module covering: declaring a certificate, the naming conventions, and the revoke-and-reissue procedure for a compromised or changed certificate.

Add a short revoke-and-reissue section that covers `ca-revoke` and the newest-serial rule.

**Verify:** in a VM test modelled on `modules/checks/nfs-cert.nix`: two throwaway test services on different nodes authenticate each other with mTLS using certificates from this module; renewal triggers the configured action; changing the declared role produces a drift-check failure; a token without a role, or a host-supplied `--set role=`, does not produce an OU; issued certificates carry the CRL distribution point, and a revoked serial appears in the CRL fetched from `http://crl.gio.ninja/`.

---

## Phase 2a: Backend cluster

Runs on every cluster member. Caddy (with the `caddy-l4` and `caddy-oidc` plugins, already compiled) runs on every member.

### Certificates (via the Phase 1 module)

| Certificate CN | OU | DNS SANs | Used by | onRenew |
|---|---|---|---|---|
| `telemetry-node.<member>` | `telemetry-cluster` | `<member>.gio.ninja` | caddy-l4 internal listeners (server side) and every caddy-l4 tunnel to a peer (client side) | reload-caddy |

One certificate covers both roles because every listener and tunnel runs in the same Caddy process: separate per-service client certificates would all be held by that one process and add enrollment work without isolation. Alertmanager gossip runs in its own process and keeps its own certificate (Phase 2c).

### Packages

nixpkgs builds `victoriametrics` from the single-node tag, so `vminsert`, `vmselect` and `vmstorage` are never built, and `victorialogs` leaves `vlagent` out by default. giopkgs provides both as overrides of the nixpkgs packages (a `victoriametrics` override pinned to the `v<version>-cluster` tag, and `victorialogs.override { withVlAgent = true; }`). The nixpkgs `vlagent` module takes a single `remoteWrite.url`, so `vlagent` needs extra args or a custom unit for multiple targets.

### Local services (all bind to 127.0.0.1 only)

| Service | Port(s) | Notes |
|---|---|---|
| `vmstorage` | 8400 (vminsert API), 8401 (vmselect API), 8482 (HTTP) | |
| `vminsert` | 8480 | `-replicationFactor=2` |
| `vmselect` | 8481 | `-replicationFactor=2`, `-dedup.minScrapeInterval=1ms` |
| VictoriaLogs (single-node) | 9428 | |
| `vlagent` | 9429 | |

- Use open-source VictoriaMetrics cluster binaries. Use nixpkgs modules where they exist; otherwise write systemd units (DynamicUser, StateDirectory, hardening).
- Set `-dedup.minScrapeInterval=1ms` on `vmstorage` as well.
- Keep replication factor at 2 when more members are added.
- Retention periods for `vmstorage` and VictoriaLogs are module options (see open items).
- `vminsert` and `vmselect` `-storageNode` lists: the local `vmstorage` directly via 127.0.0.1, plus one local caddy-l4 tunnel port per peer.
- `vlagent` writes to the local VictoriaLogs directly and to each peer's VictoriaLogs via a local caddy-l4 tunnel. Use the remote-write path documented for the deployed VictoriaLogs version (`/internal/insert` or `/insert/native`). Enable its on-disk buffer.

**Required code comment** next to the dedup flags:

> Dedup is 1ms because it only needs to collapse identical replicas (replication factor 2) and retried batches. No vmalert recording rules are used. vmalert runs on every cluster member; if recording rules are ever added, each member writes them at slightly different times. In that case either raise `-dedup.minScrapeInterval` on vmselect and vmstorage to the rule evaluation interval (and keep scrape intervals at or above it), or run recording rules on a single member.

### Internal cluster traffic: caddy-l4

All member-to-member traffic goes through caddy-l4 with mTLS. Define the internal services once and generate listeners and tunnels from the member list:

Every internal service allows exactly the client CNs `telemetry-node.<every member>`, generated from the member list:

| Internal service | Port |
|---|---|
| vmstorage (insert) | 8400 |
| vmstorage (select) | 8401 |
| vminsert | 8480 |
| vmselect | 8481 |
| VictoriaLogs | 9428 |
| vlagent | 9429 |
| Alertmanager web (Phase 2c) | 9093 |

**Server side (on each member):** a layer4 listener on the member's LAN IP at the same port number (not 0.0.0.0) that:

- terminates TLS with the `telemetry-node.<member>` certificate,
- uses `client_auth` with `mode require_and_verify` and a `trust_pool` containing the step-ca root,
- allows only the listed CNs, matched with `vars {l4.tls.client.subject.common_name} <cn> ...` (list generated from the member list), and rejects everything else,
- proxies to `tcp/127.0.0.1:<port>`.

**Client side (on each member, per peer, per internal service):** a layer4 listener on `127.0.0.1:<tunnel-port>` that proxies to `<peer>.gio.ninja:<port>` with TLS enabled, verifying the peer's certificate against the step-ca root, and presenting the member's `telemetry-node.<member>` certificate with `tls_client_auth <cert> <key>`. Derive tunnel ports deterministically from (peer index, service index) so they are stable and never collide with the local ports above.

Caddy must be reloaded when any of its certificates renew (handled by `onRenew = reload-caddy`).

### Check revocation on every client-auth listener

Every Caddy `client_auth` block on the members (the front door and every caddy-l4 server listener) adds the CRL verifier from the `caddy-revocation-validator` plugin (module `tls.client_auth.verifier.revocation`, already compiled into Caddy):

```
verifier revocation {
  mode crl_only
  crl_config {
    storage_type disk
    work_dir /var/lib/caddy/crl
    update_interval 10m
    signature_validation_mode verify
    cdp_config {
      crl_fetch_mode fetch_actively
      crl_cdp_strict true
    }
  }
}
```

- **Find the CRL through the certificates' CDP extension, not `crl_url`.** A `crl_url` that cannot be fetched when Caddy starts fails the whole config load, which on carbon would take down every site whenever strontium is unreachable at boot.
- **`crl_only`:** step-ca has no OCSP responder. Switch modes if it gains one.
- **Fail closed:** `crl_cdp_strict true` rejects a certificate whose CRL has never loaded, so a fresh member refuses clients until it reaches strontium once.
- **Strontium outages:** the plugin keeps the last CRL when a refresh fails, and `storage_type disk` keeps it across Caddy restarts. Members keep enforcing the last known revocations and nobody is locked out.
- **Plugin limits:** it ignores the CRL's `nextUpdate`, so a stale CRL stays in use indefinitely. CRL fetches have no timeout; with `fetch_actively` only the first fetch blocks handshakes, and later refreshes run in the background.
- **caddy-l4:** its TLS handler uses standard `caddytls` connection policies, so the verifier should work there unchanged. Confirm at runtime that a revoked certificate is rejected by a caddy-l4 listener.
- **Alertmanager gossip** cannot check a CRL. Its peers are cluster members only; a compromised member is removed from `clusterNodes` instead.

### Front door: `telemetry.gio.ninja`

On every member, a Caddy site for `telemetry.gio.ninja`:

- Public TLS certificate via the existing DNS-01 setup.
- `tls { client_auth { mode require_and_verify; trust_pool file <step-ca root> } }`
- Authorization by OU in the client certificate subject (`{http.request.tls.client.subject}`); confirm the exact placeholder format by logging a test request before writing matchers. The placeholder is one string (roughly `OU=...,O=app,CN=...`), so match it with an anchored regexp on the OU and O fields, never a contains-match.
- Client auth turns on `strict_sni_host` for the server (see NIXOS-137). Before deploying, confirm no existing vhost on carbon's or gallium's Caddy breaks.
- Log the client certificate CN on every request.

Routes (strip the `/metrics` or `/logs` prefix with `handle_path`):

| Path | Allowed OU | Upstream (in order, `lb_policy first`, `health_uri /health`) |
|---|---|---|
| `/metrics/insert/*` | `telemetry-writer` | local `vminsert`, then peer `vminsert` tunnels |
| `/metrics/select/*` | `telemetry-reader` | local `vmselect`, then peer `vmselect` tunnels |
| `/logs/insert/*` | `telemetry-writer` | local `vlagent`, then peer `vlagent` tunnels |
| `/logs/select/*` | `telemetry-reader` | local VictoriaLogs, then peer VictoriaLogs tunnels |
| anything else | n/a | `403` |

### Escape hatch: `push.telemetry.gio.ninja`

On every member, a write-only Caddy site with no client certificate:

- Public TLS certificate for `push.telemetry.gio.ninja` via DNS-01 (a `*.gio.ninja` wildcard does not cover it).
- Reject requests not from the LAN or WireGuard ranges (`remote_ip`, ranges taken from existing network config) with `403`.
- `basic_auth` with user `push` and a bcrypt hash delivered from the secrets system.
- `request_body { max_size 1MB }`
- Routes (same upstream ordering and health checks as the front door):

| Path | Rewritten to | Upstream |
|---|---|---|
| `/prometheus` | `/insert/0/prometheus/api/v1/import/prometheus?extra_label=source=push` | vminsert |
| `/influx` | `/insert/0/influx/write?extra_label=source=push` | vminsert |
| `/logs` | `/insert/jsonline?_stream_fields=source&extra_fields=source=push` | vlagent |
| anything else | `404` | |

Verify the query parameter names against the deployed VictoriaMetrics and VictoriaLogs versions.

Usage examples to include in the module README:

```bash
curl -u push:$TOKEN --data-binary 'backup_duration_seconds{job="restic"} 42' \
  https://push.telemetry.gio.ninja/prometheus
curl -u push:$TOKEN -d 'backup,job=restic duration=42,ok=1' \
  https://push.telemetry.gio.ninja/influx
```

Pushed values are point-in-time samples; dashboards should query them with `last_over_time(...)`.

### DNS

In the Nix-generated zone, static records derived from the member list. These are manual records (as in `modules/hosts/carbon/bifrost.nix`), not `fleet.services` endpoints, because `fleet.services` asserts each domain belongs to one host:

- `telemetry.gio.ninja` → A records for every member
- `push.telemetry.gio.ninja` → A records for every member

No health checks or dynamic records.

### Firewall

- Open 443 on members.
- Open the internal ports (8400, 8401, 8480, 8481, 9428, 9429, 9093, and 9094 from Phase 2c) on the member LAN IPs only, from other members' IPs only.

**Verify:**

1. Push a test metric and a test log line through `push.telemetry.gio.ninja`; query them from `vmselect` and VictoriaLogs on **both** members (SSH tunnel to localhost vmui).
2. Push through `telemetry.gio.ninja` with a `telemetry-writer` test certificate; confirm a certificate with another OU, or none, is rejected.
3. Confirm a caddy-l4 listener rejects a valid step-ca certificate whose CN is not in its allowed list.
4. Revoke a test `telemetry-writer` certificate with `ca-revoke`; within 10 minutes the front door rejects it on both members. Do the same for a caddy-l4 listener.
5. Stop `vmstorage` on one member: writes continue and queries return complete results. Restart it.
6. Stop Caddy on one member: clients fail over to the other via the second A record.

---

## Phase 2b: Agents on every host

Runs on every host except `aluminum`, including cluster members, Raspberry Pis (rhodium, strontium), desktops (cadmium, cesium) and `oganesson`. Roll out to carbon and gallium first, then one Raspberry Pi, then the rest. The existing Alloy/Loki shipping and central Prometheus scraping stay running in parallel.

- `oganesson` reaches the LAN only over WireGuard and gets DNS from Oracle's DHCP. Confirm it resolves `telemetry.gio.ninja` to the member LAN IPs and routes them over the tunnel.
- `cesium` is a travel machine and is often off the LAN; the agent buffers until it is back.

### Certificates

| Certificate CN | OU | Used by | onRenew |
|---|---|---|---|
| `vmagent.<host>` | `telemetry-writer` | vmagent | restart |
| `journal-upload.<host>` | `telemetry-writer` | systemd-journal-upload | restart |

### Exporters

- Keep the existing exporters as they are for now (node exporter on port 9000, zfs exporter, postgres exporter where enabled).
- Add process-exporter (`services.prometheus.exporters.process`) on 127.0.0.1 with a catch-all group by command name (`name = "{{.Comm}}"`, `cmdline = [ ".+" ]`).

### vmagent

- Scrapes the local exporters. On cluster members, also scrapes the local `vmstorage`, `vminsert`, `vmselect`, VictoriaLogs, `vlagent`, and (from Phase 2c) `vmalert` and Alertmanager `/metrics` endpoints.
- Scrape interval 15s.
- Every series gets a `host="<hostname>"` label; set `instance` to the hostname rather than `localhost:<port>`.
- Remote write to `https://telemetry.gio.ninja/metrics/insert/0/prometheus/api/v1/write` with the `vmagent.<host>` client certificate.
- On-disk buffer enabled with a size cap (keep it small on Raspberry Pis).

### systemd-journal-upload

- Enable `systemd-journal-upload` with URL `https://telemetry.gio.ninja/logs/insert/journald` (journal-upload appends `/upload`).
- Configure `ServerKeyFile=`, `ServerCertificateFile=` (the `journal-upload.<host>` certificate) and `TrustedCertificateFile=` (system CA bundle, since the front door uses a public certificate).
- Confirm that `vlagent` accepts the journald protocol on the deployed version; this is the first thing to test in this phase (see open items).

**Verify:** every host appears in VictoriaMetrics (`up` by `host`) and in VictoriaLogs (logs per host and unit); data lands on both members; agents buffer and recover when `telemetry.gio.ninja` is unreachable for a few minutes.

---

## Phase 2c: Alerting

Runs on every cluster member.

### Certificates

| Certificate CN | OU | DNS SANs | Used by | onRenew |
|---|---|---|---|---|
| `alertmanager.<member>` | `telemetry-cluster` | `<member>.gio.ninja` | Alertmanager gossip TLS | restart |

The vmalert → peer Alertmanager tunnel is a caddy-l4 tunnel and uses `telemetry-node.<member>` (Phase 2a).

### Alertmanager

- Prometheus Alertmanager (`services.prometheus.alertmanager`) on every member.
- Web/API on 127.0.0.1:9093; peers reach it through the caddy-l4 internal service (Phase 2a table).
- Gossip cluster on port 9094 with `--cluster.peer` for every other member, and `--cluster.tls-config` (experimental mutual TLS for gossip) using the `alertmanager.<member>` certificate and the step-ca root.
- Restart on certificate renewal.
- Routes:
  - `alertname="Watchdog"` → webhook receiver posting to the healthchecks.io ping URL (from secrets), `group_wait` short, `repeat_interval: 5m`.
  - Default route → Pushover receiver (the same notification path Netdata uses today), with the token and user key from the secrets system.
- Create the healthchecks.io check by hand (period 5 minutes, grace 10 minutes), as the heartbeat checks are, and deliver its ping URL as the `telemetry_watchdog_url` credential.

### vmalert

Two instances per member:

- **Metrics:** `-datasource.url=http://127.0.0.1:8481/select/0/prometheus`
- **Logs:** `-rule.defaultRuleType=vlogs`, `-datasource.url=http://127.0.0.1:9428`

Both instances:

- `-notifier.url` for the local Alertmanager (127.0.0.1:9093) and one per peer via the caddy-l4 tunnels.
- No recording rules, and no remote write.
- **Identical configuration on every member**, with no member-specific external labels.

**Required code comment** next to the vmalert config:

> vmalert runs on every cluster member and sends every alert to every Alertmanager. Alertmanager only deduplicates alerts with identical labels, so this config must stay identical across members: never add member-specific labels (e.g. `-external.label=node=...`), or every notification will be sent once per member.

(Also place the dedup comment from Phase 2a here or reference it.)

### Initial rules

- `Watchdog`: always firing (`vector(1)`).
- Host/exporter down (`up == 0`, and absence of a host's series for 5 minutes).
- Memory usage above 90% for 10 minutes.
- Filesystem space low.
- ZFS pool not healthy (where the zfs exporter runs).
- Ingestion problems: vminsert/vmstorage errors, vlagent buffer growing.

**Verify:** a test alert produces exactly one notification while both members are up, and still one when one member is stopped; the healthchecks.io check stays green; stopping Alertmanager on both members turns it red within the grace period.

---

## Phase 3: Web UIs (carbon only)

All human-facing traffic goes to carbon.

### DNS

In the Nix-generated zone: `grafana.gio.ninja`, `vmui.gio.ninja`, `logs.gio.ninja`, `alertmanager.gio.ninja` → A record for carbon only.

### Grafana

- Extend the Grafana already running on carbon (`modules/hosts/carbon/grafana.nix`, `grafana.gio.ninja`) rather than starting a second one.
- Listens on 127.0.0.1; Caddy site `grafana.gio.ninja` reverse-proxies to it.
- Native OIDC login with Pocket ID (generic OAuth), with roles mapped from Pocket ID groups.
- Provisioned data sources, all pointing at carbon's local services (no Caddy, no client certificates):
  - VictoriaMetrics: `http://127.0.0.1:8481/select/0/prometheus`
  - VictoriaLogs (VictoriaLogs data source plugin): `http://127.0.0.1:9428`
  - Alertmanager: `http://127.0.0.1:9093`
- Provisioned dashboards: node exporter, process-exporter (top processes by memory and CPU), VictoriaMetrics cluster, VictoriaLogs.

### caddy-oidc for UIs without their own login

- Global `oidc` block: Pocket ID issuer, client ID and secret from `{env.*}` (secrets delivered via EnvironmentFile), `scope openid email profile groups`, `username email`.
- Shared snippet applied to each UI site:
  - `authenticate cookie` only (no bearer), with a 32- or 64-byte secret from env, `claim groups`, `max_age 168h`.
  - `allow { user *; claim groups <admin group> }`. Every allow rule must include a user match.
- Sites:
  - `vmui.gio.ninja` → `127.0.0.1:8481` (vmui at `/select/0/vmui/`)
  - `logs.gio.ninja` → `127.0.0.1:9428` (UI at `/select/vmui`)
  - `alertmanager.gio.ninja` → `127.0.0.1:9093`
- Register each site's `/oauth2/callback` URL with the Pocket ID client.
- Include `{http.auth.user.id}` in Caddy access logs for these sites.

**Verify:** login through Pocket ID works for each UI; a user outside the admin group is denied; a request with only a bearer token is rejected; Grafana dashboards show data from all hosts.

---

## Phase 4: Cutover and cleanup

Only after the new stack has run in parallel long enough to trust it:

1. Point any remaining dashboards and alerts at the new stack.
2. Remove the `send-metrics` aspect (Alloy, journald → Loki) and retire Loki.
3. Stop central Prometheus scraping and retire the old Prometheus server.
4. Remove Netdata.
5. Bind all exporters (node, zfs, postgres, process) to 127.0.0.1 and remove their firewall openings (including the postgres exporter's `openFirewall`).
6. Check and set connect timeouts for `vmagent` and `systemd-journal-upload` so a hung member is skipped quickly.

---

## Follow-up (after Phase 4): Perses

Grafana stays as the dashboard tool for this plan. As a separate follow-up project, evaluate Perses as a replacement:

- Dashboards defined fully as code in the NixOS config and provisioned statically (no click-built dashboards).
- Runs on carbon behind Caddy, reading the same local endpoints as Grafana (`vmselect`, VictoriaLogs).
- Check before committing: nixpkgs packaging, support for a VictoriaLogs (or other logs) data source, and OIDC login with Pocket ID (otherwise front it with caddy-oidc).
- Run alongside Grafana until the dashboards are ported, then retire Grafana.

---

## Open items to resolve during implementation

- Whether `vlagent` accepts the journald protocol. Test this first, at the start of Phase 2a, before writing the front-door logs route.
- NixOS units for `vminsert`, `vmselect`, `vmstorage` and multi-target `vlagent` (the packages come from giopkgs).
- Retention periods and disk sizing for `vmstorage` and VictoriaLogs.
- Pocket ID group name for UI access.
- How long to run in parallel before Phase 4, and whether any historical Prometheus data is migrated.
