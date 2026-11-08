# Telemetry and mTLS

This page describes the push-based telemetry stack and the mTLS certificate system it runs on, as built. The code lives in `modules/aspects/mtls/`, `modules/aspects/telemetry/`, `modules/aspects/telemetry-agent/`, `modules/aspects/telemetry-alerting/` and `modules/hosts/strontium/`.

## Understand the architecture

### Hosts and roles

- **Cluster members** are `carbon` and `gallium`. They run the VictoriaMetrics cluster, VictoriaLogs, alerting and the Caddy front door. They include `den.aspects.telemetry-member`.
- **carbon** also serves the human-facing UIs (`fleet.telemetry.ui.host`).
- **Every host except `aluminum`** runs the agent (`den.aspects.telemetry-agent`): exporters, `vmagent` and `systemd-journal-upload`. That includes the members, rhodium, strontium, oganesson, cadmium and cesium.
- **strontium** runs step-ca, the CRL endpoint and the enrollment tools.

### Data flow

- **Metrics:** exporters on localhost, then `vmagent`, then `https://telemetry.gio.ninja/metrics/...` with an mTLS client certificate, then Caddy, then `vminsert`, then `vmstorage` on every member (replication factor 2).
- **Logs:** journald, then `systemd-journal-upload`, then `https://telemetry.gio.ninja/logs/...` (mTLS), then Caddy, then `vlagent`, then VictoriaLogs on every member.
- **Queries:** Grafana on carbon reads carbon's local `vmselect` and VictoriaLogs directly.
- **Alerts:** `vmalert` on every member sends to the Alertmanager on every member (gossip-clustered). Notifications go to Pushover, and a Watchdog ping goes to healthchecks.io.
- **Member to member:** all internal traffic runs through caddy-l4 listeners and tunnels with mTLS.

### Edit the member list

`fleet.telemetry.clusterNodes` (default `["carbon" "gallium"]`) is the single source of truth. Storage node lists, caddy-l4 listeners, tunnels, allowed CNs, front-door upstreams, `vlagent` write targets, firewall rules, DNS records and gossip peers all derive from it.

The list is append-only. The tunnel ports depend on member position (see [Understand the tunnel ports](#understand-the-tunnel-ports)). The backend asserts at least two members, because `replicationFactor=2`.

Retention is `fleet.telemetry.retention.metrics` (90d) and `.logs` (30d).

## Understand the CA side

strontium's step-ca has a JWK provisioner named `app` that issues every certificate declared with `gio.mtls.certs`. It is defined in `modules/hosts/strontium/_ca-config.nix` and written into `ca.json` by `step-ca-provisioners.service`.

- **Subject:** `CN=<app>.<host>`, `O=app` and `OU=<role>`. Only the `app` template sets an OU, so an OU match also proves the certificate came from `app`. The `nfs` provisioner sets `O=nfs`.
- **Lifetime:** 7 days, default and maximum.
- **Renewal:** `mtls-renew.timer` runs every 12 hours and renews with `--expires-in 120h`, so a certificate renews once it is about 2 days old. That leaves about 5 days of CA outage before anything expires.
- **After expiry:** `--allow-renewal-after-expiry=false`. A stolen expired certificate cannot renew, and a host that was off for more than 7 days needs re-enrolling.
- **Key usage:** both `serverAuth` and `clientAuth`.

### Keep the template on `.Token` only

`modules/hosts/strontium/app-x509.tpl` reads the CN, SANs and role only from `.Token.*`, which the provisioner key signed on strontium. Never read `.Insecure.*`. `.Insecure.User` is whatever the requesting host passes to `step ca certificate --set`, so reading it lets a host pick its own role.

The role arrives as `--set role=<role>` on `step ca token`, which step-cli puts in the token's `user` claim. A token without a role fails the template. Renewal copies the old certificate, so subject and SANs never change after issuance.

### Serve the CRL over plain HTTP

step-ca publishes a CRL (`generateOnRevoke = true`, so it rebuilds the moment you revoke). nginx on strontium serves it at `http://crl.gio.ninja/` on port 80, proxying to step-ca's `/1.0/crl` (`modules/hosts/strontium/_crl-http.nix`). Every `app` certificate names it as its CRL distribution point.

It is plain HTTP on purpose:

- The CRL is signed by the CA, so the transport needs no trust, and verifiers never need TLS to check TLS.
- step-ca's own HTTPS endpoint chains to the step-ca root, which is in no system trust store. Adding that root to system trust would let it vouch for any hostname, because step-ca has no name constraints.

step-ca has no OCSP responder, so the template has no OCSP URL. If step-ca gains one, add the URL to the template and re-enroll every host: renewal copies extensions, so existing certificates never gain it.

## Declare a certificate

Declare certificates in NixOS config under `gio.mtls.certs.<name>`. The aspect is on every host through `den.default` and does nothing until a host declares one.

```nix
gio.mtls.certs.vmagent = {
  role = "telemetry-writer";
  services = ["vmagent"];
  onRenew = "restart";
};

gio.mtls.certs.telemetry-node = {
  role = "telemetry-cluster";
  serverHostnames = ["carbon.gio.ninja"];
  serverAddresses = ["10.30.0.10"];
  onRenew = "reload-caddy";
};
```

| Option | Meaning |
|---|---|
| `app` | Application name. Defaults to the attribute name. |
| `role` | Signed into the certificate as the OU. Callers are authorized by it. |
| `serverHostnames` | DNS SANs. Only names that resolve to this host; pure clients have none. |
| `serverAddresses` | IP SANs, for peers that dial and verify by IP. Only addresses of this host, in canonical form (`fd00::1`), because the drift check compares them verbatim. |
| `services` | systemd services that consume the certificate (`.service` optional). |
| `onRenew` | `restart` or `reload` the `services`, or `reload-caddy` (`systemctl reload caddy`). |

Read-only values for consumers:

- `cn` and `uri`: the derived identity.
- `certFile` and `keyFile`: `/var/lib/mtls/<name>/cert.pem` and `key.pem`, owned by root. With `onRenew = "reload-caddy"` they are group-readable by `caddy`, so Caddy reads them directly and picks up a renewal on reload.
- `gio.mtls.caRoot`: `/etc/step/ca-root.crt`, the trust pool for verifying peers.

### Follow the naming conventions

For application `<app>` on host `<host>`:

- **CN:** `<app>.<host>`
- **URI SAN:** `spiffe://gio.ninja/<host>/<app>`
- **DNS SANs:** only for services that also act as servers, and only for names that resolve to this host.
- **IP SANs:** only addresses that belong to this host.

Authorize callers by CN or OU, never merely by "has a valid certificate". The module asserts that no two certificates on a host share a CN.

### Know what consumer units receive

Each unit in `services` gets `LoadCredential=` for `mtls-<name>-cert`, `mtls-<name>-key` and `mtls-ca`, readable at `$CREDENTIALS_DIRECTORY/<id>`. This works with `DynamicUser=`.

systemd copies credentials when the unit starts, so a unit that only reloads keeps the old certificate in its credentials directory. Use `reload` only for services that read `certFile` themselves.

### Keep consumers dormant until enrolled

`LoadCredential=` fails a unit whose file is missing. So each consumer gets `ConditionPathExists=` on its certificates and is skipped (not failed) before enrollment. `mtls-enroll` starts it after enrolling. `mtls-renew.service` is likewise skipped until at least one certificate exists.

## Enroll a host

1. Deploy the host with the declaration, and deploy strontium so `ca-enroll-host` knows about it.
2. On strontium, run `sudo ca-enroll-host <host> mtls`. To enroll only some certificates, add `--role <role>`. It fails when the host declares no certificates or no declaration uses that role.
3. Check the CN, role and SANs it prints, then paste each printed command into a shell on the host within 30 minutes. Tokens are single-use and die if step-ca restarts.

Each pasted command drops a token into `/var/lib/mtls/tokens/`. `mtls-enroll.path` picks it up, deletes it, requests the certificate, checks it against the declaration and runs the `onRenew` action.

### Fix a failed drift check

Before every renewal, `mtls-renew` compares the CN, URI SAN, O, OU, DNS SANs and IP SANs on disk with the declaration. If they differ (a new role, another hostname), `mtls-renew.service` fails, names the certificate and stops renewing it.

When it fails:

1. Confirm the declaration is what you want. If it is not, revert the change.
2. Otherwise run `sudo ca-enroll-host <host> mtls --role <role>` on strontium and paste the output on the host. Enrollment runs the same check on the new certificate, so a token that does not match the declaration is rejected.

## Revoke and reissue a certificate

When a certificate is compromised, or its identity must change:

1. On strontium, run `sudo ca-revoke <cn>`, for example `sudo ca-revoke vmagent.carbon`.
2. Change the declaration if needed, then deploy the host and strontium.
3. Run `sudo ca-enroll-host <host> mtls --role <role>` and paste the output on the host.

`ca-revoke` reads step-ca's JSON journal and revokes the newest serial for the CN. Always revoke the newest: every renewal issues a new serial, so revoking an older one leaves the certificate in use alive.

Revocation blocks renewal, so the certificate dies within 7 days at the latest. Verifiers that check CRLs reject it sooner:

- **Caddy listeners** (the front door and every caddy-l4 listener on the members) refetch the CRL every `fleet.telemetry.crlUpdateInterval` (10 minutes), so they enforce a revocation within about 10 minutes.
- **No CRL, no access:** `crl_cdp_strict` fails closed until a member has loaded the CRL once.
- **Strontium outages:** the plugin keeps the last CRL when a refresh fails, and `storage_type disk` (`/var/lib/caddy/crl`) keeps it across Caddy restarts. Members keep enforcing the last known revocations.
- **Alertmanager gossip cannot check a CRL.** Its peers are members only. Remove a compromised member from `clusterNodes` instead. Gossip also pins peers by URI SAN.

## Operate the cluster

### Know the services and ports

Every service binds to 127.0.0.1 and is reached across members only through caddy-l4.

| Service | Local port |
|---|---|
| `vmstorage-insert` | 8400 |
| `vmstorage-select` | 8401 |
| `vminsert` | 8480 |
| `vmselect` | 8481 |
| `victorialogs` | 9428 |
| `vlagent` | 9429 |
| `alertmanager` | 9093 |

`vmstorage` HTTP is on 8482, vmalert on 8880 (metrics) and 8881 (logs), and Alertmanager gossip on 9094 (TCP only, over the member's LAN address).

Each member also opens these ports on its LAN address to the other members' addresses only, through nftables `extraInputRules`. The aspect asserts `networking.nftables.enable`.

### Understand the tunnel ports

Member A reaches member B's service through a loopback port on A:

```
tunnelPort = 21000 + peerIndex * 100 + serviceIndex
```

`peerIndex` is the peer's position in `clusterNodes` and `serviceIndex` its position in the service list in `modules/aspects/telemetry/schema.nix`. The range sits above every local port and below the ephemeral range. Both lists are append-only: inserting or reordering shifts the ports of every existing tunnel.

### Know the caddy-l4 allowlists

Each member runs a layer4 listener per service, on its own LAN address at the same port number. It terminates TLS with `telemetry-node.<member>`, requires and verifies a client certificate against the step-ca root, checks the CRL, then only proxies when the client CN is `telemetry-node.<m>` for some member `m`. Everyone else is dropped.

Each tunnel is a loopback listener that dials the peer with TLS, verifies the peer against the step-ca root and presents the member's own `telemetry-node` certificate. One certificate serves both sides because every listener and tunnel runs inside the same Caddy process.

### Use the front door

`telemetry.gio.ninja` is a Caddy site with a public certificate (DNS-01) and `client_auth require_and_verify`. Authorization is by the OU in the client subject, matched with an anchored regexp on `CN=...,OU=<role>,O=app`. Go prints the subject in RFC 2253 order, last RDN first, and the front door logs it on every request as `client_subject`.

| Path | OU | Allowed paths | Upstream |
|---|---|---|---|
| `/metrics/...` | `telemetry-writer` | `/insert/<n>/prometheus/api/v1/write` only | local `vminsert`, then peers |
| `/metrics/...` | `telemetry-reader` | named Prometheus query endpoints only | local `vmselect`, then peers |
| `/logs/...` | `telemetry-writer` | `/insert/journald/upload` only | local `vlagent`, then peers |
| `/logs/...` | `telemetry-reader` | named LogsQL query endpoints only | local VictoriaLogs, then peers |
| anything else | any | none | `403` |

The select routes are read-only because the backends serve destructive endpoints (`delete_series`, graphite `delSeries`, cache resets, `/delete/*` tasks) without an auth key. Only the listed query paths pass.

Upstreams use `lb_policy first` with `lb_try_duration 5s` and `health_uri /health`, so a member prefers its own backend and fails over to a peer. DNS gives both A records for `telemetry.gio.ninja`, so clients also fail over when a member's Caddy is down.

No host declares a `telemetry-reader` certificate today. Grafana reads locally.

### Use the push site

`push.telemetry.gio.ninja` is a write-only site for scripts that cannot hold a certificate. It accepts only these source ranges (`fleet.telemetry.pushAllowedRanges`): `10.0.0.0/16`, `10.30.0.0/24` and `10.100.0.0/24` (the LAN, the server VLAN and the WireGuard clients). Everything else gets `403`. It requires basic auth as user `push`, with the bcrypt hash in the `push_basic_auth_hash` credential, and limits bodies to 1MB.

| Path | Goes to |
|---|---|
| `/prometheus` | `vminsert` Prometheus text import |
| `/influx` | `vminsert` Influx line protocol |
| `/logs` | `vlagent` JSON lines |
| anything else | `404` |

Each rewrite replaces the whole query string, and the site strips the `AccountID`, `ProjectID` and `VL-*` headers. A pusher cannot add or override labels, fields or the tenant. Every pushed series and log line gets `source=push`.

## Push data

Pushed values are point-in-time samples. Query them with `last_over_time(...)`.

```bash
curl -u push:$TOKEN --data-binary 'backup_duration_seconds{job="restic"} 42' https://push.telemetry.gio.ninja/prometheus
curl -u push:$TOKEN -d 'backup,job=restic duration=42,ok=1' https://push.telemetry.gio.ninja/influx
curl -u push:$TOKEN -d '{"_msg":"backup finished","job":"restic"}' https://push.telemetry.gio.ninja/logs
```

Query the first with `last_over_time(backup_duration_seconds{source="push"}[1d])`. The Influx line becomes the series `backup_duration` and `backup_ok` (measurement and field joined with `_`). The site sets the logs `Content-Type` itself: VictoriaLogs reads query parameters with `FormValue`, which would swallow curl's default `x-www-form-urlencoded` body and ingest nothing.

## Query data

- **Grafana** (`grafana.gio.ninja`, carbon) has provisioned datasources for VictoriaMetrics (`http://127.0.0.1:8481/select/0/prometheus`), VictoriaLogs (`http://127.0.0.1:9428`) and Alertmanager (`http://127.0.0.1:9093`). The old Prometheus and Loki datasources remain during the parallel run. The provisioned dashboards (node exporter, process exporter, VictoriaMetrics cluster, VictoriaLogs) are pinned to VictoriaMetrics.
- **vmui** (`vmui.gio.ninja`), **logs** (`logs.gio.ninja`) and **alertmanager** (`alertmanager.gio.ninja`) are caddy-oidc sites on carbon. They accept a Pocket ID session cookie only, never a bearer token, and require membership in `fleet.telemetry.ui.adminGroup` (default `telemetry_admin`). Access logs carry the Pocket ID email as `user_id`.
- **Agents** label every series with `host` and `instance` set to the hostname.

## Understand alerting

`vmalert` runs two instances per member (metrics and logs). Both send every alert to the local Alertmanager and to each peer's through the tunnels. Alertmanager deduplicates only alerts with identical labels, so the configuration must stay identical on every member, with no member-specific labels such as `-external.label=node=...`. Otherwise every notification goes out once per member.

The metric rules are in `modules/aspects/telemetry-alerting/_rules.nix`; there are no log rules yet:

- `Watchdog`: always firing.
- `TargetDown`: `up == 0` for 5 minutes.
- `HostSilent`: a host that sent `up` in the last day but not in the last 5 minutes. A dead agent writes no `up` at all, so `TargetDown` cannot catch it.
- `MemoryHigh`, `FilesystemSpaceLow` and `ZfsPoolUnhealthy`.
- Ingestion health: `VictoriaMetricsRequestErrors`, `VictoriaMetricsRpcErrors`, `VictoriaMetricsRowsIgnored`, `VlagentDroppingData`, `VlagentRemoteWriteErrors` and `VlagentBufferGrowing`.

Routing:

- The default route goes to Pushover (`telemetry_pushover_app_token` and `telemetry_pushover_user_token`).
- `Watchdog` goes to the webhook in `telemetry_watchdog_url`, a healthchecks.io ping URL, every 5 minutes. Create the check with a 5-minute period and a 10-minute grace. It turns red if the whole pipeline stops.

Gossip runs TLS with `alertmanager.<member>` certificates and accepts only peers whose URI SAN is `spiffe://gio.ninja/<member>/alertmanager`.

## Roll out in waves

`den.aspects.telemetry-member` includes different things depending on `fleet.telemetry.cluster.enable`.

| Wave | State | What runs |
|---|---|---|
| A | Committed default | Every host gets the agent, dormant until enrolled. Members also run the backend and declare their `telemetry-node` and `alertmanager` certificates. Caddy is untouched. |
| B | `fleet.telemetry.cluster.enable = true` | Members add alerting, the Caddy front door, the push site, caddy-l4 tunnels and DNS (`dns.enable` follows it). |
| C | `fleet.telemetry.ui.enable = true` and `gio.grafana.oidc.enable = true` | The caddy-oidc UIs with their DNS records, and Pocket ID login for Grafana. |

Set the two `fleet.telemetry.*` flags at the top level of a flake module, not inside a `.nixos` block: they are flake-level fleet values. Add them to the `config` block of `modules/fleet.nix`; `modules/hosts/carbon/default.nix` sets `fleet.backups` at top level the same way. `gio.grafana.oidc.enable` is a NixOS option on carbon, so set it inside `den.aspects.carbon.nixos`, for example in `modules/hosts/carbon/grafana.nix`.

## Follow the rollout runbook

Deploy carbon and gallium together at every step that changes them: they mirror each other.

### Deploy Wave A

1. Deploy all seven hosts: carbon and gallium together, then rhodium, strontium, oganesson, cadmium and cesium.
2. Check that `systemctl --failed` is empty on each.
3. Check that `vmagent` and `systemd-journal-upload` are skipped (`systemctl show -p ConditionResult vmagent` says `no`).
4. Check that Caddy validates and every existing site works.

### Enroll the members

1. On strontium, run `sudo ca-enroll-host carbon mtls --role telemetry-cluster`, then the same for gallium. Paste each output on its host.
2. Check that `/var/lib/mtls/telemetry-node/cert.pem` and `/var/lib/mtls/alertmanager/cert.pem` exist on each member.
3. Run `systemctl start mtls-renew` and check that it succeeds.

### Create the Wave B secrets

Create these on carbon and gallium:

- `push_basic_auth_hash`: the output of `caddy hash-password`.
- `telemetry_pushover_app_token` and `telemetry_pushover_user_token`.
- `telemetry_watchdog_url`: the ping URL of a healthchecks.io check with a 5-minute period and 10-minute grace.

In the secrets repo, run `agevault write <host> <name> -` for each secret on each member, piping the value on stdin (or `agevault edit <host> <name>`). Both commands regenerate the names-only manifest. Copy the regenerated `secrets.toml` into this repo and commit it, then run `agevault push <host>` to deliver the credentials to each member's credstore.

### Flip Wave B

1. Set `fleet.telemetry.cluster.enable = true` in the `config` block of `modules/fleet.nix` and deploy carbon and gallium together.
2. Phase 2a checks:
   - Push through the push site and query the data on both members.
   - Check that a certificate with another OU is rejected at the front door.
   - Check that a caddy-l4 listener rejects a valid certificate whose CN is not a member.
   - Check that `ca-revoke` of a test certificate is enforced within 10 minutes.
   - Stop `vmstorage` on one member: writes and queries continue.
   - Stop Caddy on one member: clients fail over to the other.
3. Phase 2c checks:
   - A test alert produces exactly one notification with both members up, and still one with one member stopped.
   - The healthchecks.io check stays green.
   - Stopping Alertmanager on both members turns the Watchdog check red within the grace period.

### Enroll the writers

Enroll carbon and gallium first, then one Raspberry Pi, then the rest. On strontium, for each host:

```bash
sudo ca-enroll-host <host> mtls --role telemetry-writer
```

Paste the output on the host, then check that every host appears in `up` by `host`, that logs arrive per host and unit, and that the agents buffer through a short outage of `telemetry.gio.ninja`.

Do this only after Wave B: `systemd-journal-upload` restart-loops if `telemetry.gio.ninja` does not resolve.

### Roll out Wave C

1. Decide the admin group (`fleet.telemetry.ui.adminGroup`, default `telemetry_admin`).
2. Create two Pocket ID clients:
   - **Grafana:** callback `https://grafana.gio.ninja/login/generic_oauth`. Secrets: `grafana_oidc_client_id` and `grafana_oidc_client_secret`.
   - **caddy-oidc:** callbacks `https://vmui.gio.ninja/oauth2/callback`, `https://logs.gio.ninja/oauth2/callback` and `https://alertmanager.gio.ninja/oauth2/callback`. Secrets: `telemetry_ui_oidc_client_id`, `telemetry_ui_oidc_client_secret` and `telemetry_ui_oidc_cookie_secret` (from `openssl rand -hex 16`).
3. Create the secrets on carbon with `agevault`, as in Wave B.
4. Set `fleet.telemetry.ui.enable = true` in the `config` block of `modules/fleet.nix`, and `gio.grafana.oidc.enable = true` inside `den.aspects.carbon.nixos` (in `modules/hosts/carbon/grafana.nix`). Then deploy carbon and gallium together.
5. Check that Pocket ID login works, that a non-admin user is denied, that a bearer-only request is rejected, and that Grafana shows every host.

## Know the limits and gotchas

- **421 without SNI.** Client auth turns on `strict_sni_host` for the server, so on the members every `:443` connection by IP, or with a `Host` that does not match its SNI, gets a `421`. The `telemetry-cluster` VM test checks that the other vhosts still work.
- **The CRL plugin needs a patch.** step-ca marks its CRL's Issuing Distribution Point extension critical (RFC 5280 section 5.2.5). `caddy-revocation-validator` v1.0.7 refuses it as unhandled, so with `crl_cdp_strict` every client would be rejected. `modules/aspects/server/caddy-revocation-validator-idp.patch` makes the plugin process it, and `modules/aspects/server/reverse-proxy.nix` applies it to the Caddy build. A `REMIND-ME-TO` there asks you to submit the patch upstream and drop it once a release handles the extension.
- **Stale CRLs stay in use.** The plugin ignores the CRL's `nextUpdate`, and its fetches have no timeout. With `fetch_actively` only the first fetch blocks handshakes.
- **Caddy can be silently skipped.** Caddy on a member carries `ConditionPathExists` on its `telemetry-node` certificate. If that file is deleted, Caddy is skipped, not failed, and every site on the host goes down without an error.
- **Writers before Wave B.** Do not enroll writers before Wave B. `systemd-journal-upload` restart-loops while `telemetry.gio.ninja` does not resolve.
- **oganesson DNS is unverified.** oganesson should resolve `gio.ninja` names through `wg-lan` to carbon and gallium, but this has not been verified on the host.
- **Use HTTP/1.1 for manual curls.** The caddy-l4 listeners advertise h2, so a manual `curl` to one needs `--http1.1`.
- **Journal upload URL.** `journalUploadUrl` needs an explicit `:443`. Without a port, journal-upload appends `:19532/upload` after the path.
- **The old stack still runs.** Alloy, Loki, central Prometheus and Netdata keep running in parallel. Cutover and cleanup are not done.
- **Dedup.** `-dedup.minScrapeInterval=1ms` only collapses identical replicas and retried batches. If you add vmalert recording rules, each member writes them at slightly different times. Then raise the dedup interval on vmselect and vmstorage to the rule evaluation interval (and keep scrape intervals at or above it), or run recording rules on one member.

## Run the VM tests

The tests are flake checks, named after their files in `modules/checks/`:

```bash
nix build .#checks.x86_64-linux.mtls
nix build .#checks.x86_64-linux.telemetry-backend
nix build .#checks.x86_64-linux.telemetry-cluster
nix build .#checks.x86_64-linux.telemetry-alerting-rules
```

- `mtls`: a real step-ca built from strontium's own provisioner flags, templates, CRL endpoint and tools. Two hosts enroll, authenticate each other, renew, hit a drift failure and get revoked.
- `telemetry-backend`: two members' VictoriaMetrics and VictoriaLogs replication, and loopback-only binding.
- `telemetry-cluster`: two members with step-ca certificates, Caddy and caddy-l4. It covers the front door roles and paths, the push site, tunnels, losing a `vmstorage`, revocation at the front door and a listener, and the fail-closed no-CRL case. Public certificates are the one stand-in: Caddy's internal issuer under a fixed test root.
- `telemetry-alerting-rules`: `vmalert-tool unittest` over `modules/aspects/telemetry-alerting/tests/rules.test.yml`. It is not a VM test.
