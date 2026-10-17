# Run Unison Cloud on carbon

You run your own Unison Cloud on carbon (NIXOS-125). It went live on 2026-10-17: you can log in through Pocket ID, and ucm deploys services to it. The bottle (`inputs.unison-cloud-in-a-bottle`) does most of the work.

The bottle exports `nixosModules.core`, a module built for a host like carbon that already runs a reverse proxy, a login provider, PostgreSQL, S3, Consul and Loki. Core runs cloud-api, nimbus and Vector as plain systemd units, sandboxes them, generates its own keys, and hands you the Caddy site bodies. This repo points it at what carbon already has.

The first version of this plan hand-wrote every unit, along with a private Consul, Redis, ExtendDB and an internal CA. None of that was needed:

| First plan | What runs |
|---|---|
| Hand-written cloud-api, nimbus and Vector units | `nixosModules.core` |
| Redis | Gone. Login state lives in PostgreSQL (cloud-api patch 0009) |
| ExtendDB, its setup oneshot, the internal CA and the CA bundle bind-mount | Gone. nimbus stores its data in PostgreSQL (nimbus patches 0003 and 0004) |
| Private single-node Consul | Not needed. cloud-api sends an ACL token and prefixes its keys (patch 0010), so it joins the fleet Consul |
| Header-trust routes to patch out first | Done in the bottle (patch 0008) |
| `_secrets.nix` generating keys | Core generates them in `unison-cloud-secrets` |
| Fleet-wide node list and `worker.nix` | Core's `nimbus.nodes.interactive`. Multi-host is `cloudApi.enable`, `nimbus.cloudApiHost` and `advertiseAddress` |

## Know the shape of it

- **Domains:** `unison.gio.ninja` (UI), `api.unison.gio.ninja` (API, and `UNISON_CLOUD_HOST` for ucm) and `app.unison.gio.ninja` (deployed services). All three are same-site under gio.ninja, so the session cookie works.
- **Login:** Pocket ID, limited to the `unison_cloud` group.
- **Storage:** Garage on gallium, and carbon's PostgreSQL.
- **Logs:** carbon's existing Loki at `127.0.0.1:3100`.
- **State:** `/var/lib/unison-cloud` (core's default `stateDir`) on its own `bowl/unison-cloud` dataset, backed up.
- **External secrets:** through agevault, snake_case. Core loads each credential under its credstore name, the name agevault encrypts it with.
- **Bottle:** the lock points at `3b83e8d4`. Getting a real deploy working took three bottle fixes after `6d514b00`: cloud-api patch 0011 (PKCE verifier length), cloud-api patch 0012 (allowlist refusal reasons in the log) and nimbus patch 0005 (S3 `Content-Type`).

## Decisions

You confirmed these on 2026-10-16:

- **Consul:** the fleet Consul. carbon's agent already runs with ACLs and `default_policy = "deny"`. Core's `consul.aclPolicy` covers only `unison-cloud/` keys and `unison-cloud-*` services, so its token can't touch anything else.
- **No outbound proxy.** Only `nixosModules.core` is imported, with no batteries, so there's no Squid. Hosted code reaches carbon's loopback, the LAN and the internet directly, for homelab automation. That includes Loki, which has no auth, and every other unauthenticated service on loopback. A bug in your own code can hit them.
- **PostgreSQL:** carbon's server. One oneshot creates both roles with passwords, their databases and the three extensions. The two passwords are agevault secrets.
- **Logs:** carbon's Loki, plus the Vector unit that core runs. Nothing new to deploy. See [Know where the logs go](#know-where-the-logs-go).

## Know where the logs go

carbon already ships its whole journal to Loki through Alloy (`send-metrics`), labelled by `unit` and `hostname`. So every `unison-cloud-*` unit, cloud-api and the nimbus nodes included, shows up in Grafana with no extra work, for example `{unit=~"unison-cloud-.*"}`.

Core's Vector (`unison-cloud-log-shipper`) is separate, and you still need it. It ships only the nimbus lines about a user's job, with the zero-width space stripped and `userId` as structured metadata, under the fixed labels cloud-api queries: `{job="nomad_allocs", namespace="user", task_name="nimbus"}`. That's what makes `Cloud.logs`, `logs.tail` and the UI's log view work. The labels are fixed by cloud-api's query, so they can't become the fleet's labels.

Those user lines reach Loki twice: raw through Alloy, and cleaned up through Vector. That's a small amount of duplication.

Alloy could do Vector's job with a second pipeline, but core always runs Vector when nimbus is on, so dropping it would need a bottle option or an `mkForce`. Keeping Vector is simpler.

## Lay out the aspect

`modules/aspects/server/unison-cloud/` holds one aspect, `den.aspects.unison-cloud`. import-tree skips the `_` file; `default.nix` imports it. The carbon-only parts live in `modules/hosts/carbon/unison-cloud.nix`, because test fleets import every aspect file but skip `/hosts/`.

| File | Contents |
|---|---|
| `aspects/server/unison-cloud/default.nix` | Imports `nixosModules.core`, sets `services.unison-cloud`, its credentials, the three Caddy vhosts and the Consul ordering |
| `aspects/server/unison-cloud/_postgresql.nix` | The roles, their databases and the setup oneshot |
| `aspects/consul/consul.nix` | `consul-ready.service`, which the Consul registration waits for |
| `hosts/carbon/unison-cloud.nix` | Includes the aspect on carbon, the `bowl/unison-cloud` dataset, the DNS-only endpoints with the healthcheck, and the backup entry |
| `checks/unison-cloud.nix` | The VM test |

## Configure core

```nix
services.unison-cloud = {
  enable = true;
  domains = {
    api = "api.unison.gio.ninja";
    apps = "app.unison.gio.ninja";
    ui = "unison.gio.ninja";
  };

  auth.oidc = {
    issuer = "https://login.gio.ninja";
    clientId = "c76c9f5f-c479-4cba-8ed3-f0b0be817597";
    # The browser follows the public URL; cloud-api talks to Pocket ID directly.
    endpoints = {
      authorization = "https://login.gio.ninja/authorize";
      token = "http://127.0.0.1:1411/api/oidc/token";
      jwks = "http://127.0.0.1:1411/.well-known/jwks.json";
    };
    allowedGroups = ["unison_cloud"];
  };

  s3 = {
    host = "s3.garage.gio.ninja";
    region = "garage";
  };

  database.host = "127.0.0.1";
  logs.lokiUrl = "http://127.0.0.1:3100";

  secrets.credentials = {
    oidc-client-secret = "unison_cloud_oidc_client_secret";
    s3-access-key-id = "unison_cloud_s3_access_key_id";
    s3-secret-access-key = "unison_cloud_s3_secret_access_key";
    cloud-api-db-password = "unison_cloud_api_db_password";
    nimbus-db-password = "unison_cloud_nimbus_db_password";
    consul-token = "unison_cloud_consul_token";
  };
};

fleet.credentials.needs = [ /* the six names above */ ];
```

`allowedGroups` must match the group's **Name** in Pocket ID, which is what the `groups` claim carries, not its friendly name.

The S3 defaults already fit Garage: port 443, HTTPS, and virtual-host addressing, which gallium serves through its `*.s3.garage` endpoint. The bucket defaults are `unison-cloud-services` and `unison-cloud-user-blobs`.

Ports start at 24100 for cloud-api and 24200 for nimbus. Nothing on carbon uses them, and core opens no firewall ports.

## Add the ingress

`siteConfig` lives in carbon's NixOS config, which endpoints, declared at the den host level, can't read. So each endpoint keeps only `domain`, for DNS, and the aspect sets each vhost with core's site body (`cfg.caddy.siteConfig.api`, `.apps` and `.ui`) through `services.gio.reverse-proxy`. The API body already 404s `/internal/*` and strips `X-Auth-Request-*`.

The healthcheck points at `https://api.unison.gio.ninja/.well-known/openid-configuration`. It needs no login, and a 200 means Caddy and cloud-api are up.

## Set up PostgreSQL

`_postgresql.nix` adds a oneshot that runs as `postgres` before `unison-cloud-database.service`. It loads the two password credentials and runs SQL like the battery's own setup:

- `unison_cloud`, which owns database `unison_cloud`, with `uuid-ossp`, `citext` and `moddatetime`;
- `unison_cloud_nimbus`, which owns database `unison_cloud_nimbus`;
- `REVOKE ALL ... FROM PUBLIC` on both, so neither role reads the other's tables.

Both roles log in over `127.0.0.1` with a password, which NixOS's default `host all all 127.0.0.1/32` rule already allows.

## Wait for Consul before registering

`consul.service` is `Type=simple`, so systemd counts it as started before the agent can resolve ACL tokens. On the first deploy, `unison-cloud-consul-services` ran while Consul was restarting and failed with `403 ACL not found`, even though the token was valid.

`consul-ready.service`, in the consul aspect, polls `/v1/status/leader` until the agent sees a leader. It's `partOf` `consul.service`, so it runs again whenever Consul restarts. `unison-cloud-consul-services` requires and orders after it, and also retries every 5 seconds on failure as a backstop.

## Do these steps by hand

These are done for carbon. They're kept here for rebuilding it, or for a second cloud.

### 1. Create the dataset on carbon

disko declares `bowl/unison-cloud` with a `legacy` mountpoint, so NixOS adds a mount for `/var/lib/unison-cloud`. disko doesn't create datasets on a running host, and the mount fails if the dataset is missing. Create it before you deploy:

```sh
carbon$ sudo zfs create -o mountpoint=legacy -o atime=off bowl/unison-cloud
```

Don't mount it yourself. The deploy mounts it, and core's units create their directories inside it.

### 2. Create the buckets and key on gallium

In a root shell, where the `garage` alias points at `/etc/garage.toml`:

```sh
gallium$ sudo -i
gallium$ garage bucket create unison-cloud-services
gallium$ garage bucket create unison-cloud-user-blobs
gallium$ garage key create unison-cloud
gallium$ garage bucket allow --read --write --owner unison-cloud-services --key unison-cloud
gallium$ garage bucket allow --read --write --owner unison-cloud-user-blobs --key unison-cloud
```

`garage key create` prints a key ID (`GK…`), which is the S3 access key ID, and a secret key. They go into `unison_cloud_s3_access_key_id` and `unison_cloud_s3_secret_access_key`. If you lose them, `garage key info --show-secret unison-cloud` prints them again.

The key only has access to these two buckets. cloud-api and nimbus reach them as `<bucket>.s3.garage.gio.ninja` through gallium's existing `*.s3.garage` endpoint, so gallium's config doesn't change.

### 3. Create the Pocket ID client and group

At https://login.gio.ninja, as an admin:

1. Under **User Groups**, create a group with the **Name** `unison_cloud` and add yourself to it. cloud-api only lets in members of this group (`allowedGroups`).
2. Under **OIDC Clients**, add a client:
   - **Name:** Unison Cloud.
   - **Callback URL:** `https://api.unison.gio.ninja/selfhost/oidc/callback`.
   - **Logout callback URL:** leave it empty. cloud-api's `/logout` only clears its own cookie and never sends you to Pocket ID.
   - **Launch URL:** `https://unison.gio.ninja`, for the tile on your Pocket ID dashboard.
   - **Public client:** off. cloud-api is confidential and sends a client secret.
   - **Allowed user groups:** `unison_cloud`, so Pocket ID refuses everyone else before they reach cloud-api.
3. Save, and copy the **client ID** and **client secret**. The secret is shown only once, so regenerate it if you lose it.

The secret goes into `unison_cloud_oidc_client_secret`. The client ID isn't secret; it goes inline as `clientId` in `modules/aspects/server/unison-cloud/default.nix`.

### 4. Create the Consul token

Build the policy from this repo on cadmium. It evaluates without the agevault secrets:

```sh
cadmium$ policy=$(nix build --no-link --print-out-paths "git+file:///home/giodamelio/nixos-configs?rev=$(jj log -r @ --no-graph -T commit_id)#nixosConfigurations.carbon.config.services.unison-cloud.consul.aclPolicy")
cadmium$ cat "$policy"
cadmium$ scp "$policy" carbon:/tmp/unison-cloud.hcl
```

The policy grants write access to the `unison-cloud/` keys and `unison-cloud-*` services, and read access to nodes. Check that it matches before you create it.

On carbon, `CONSUL_HTTP_TOKEN` must hold a management token: the `SecretID` that `consul acl bootstrap` printed when you turned on ACLs. This repo doesn't store it. Don't use `consul_acl_tokens`: it only holds carbon's agent token, which can't create policies.

```sh
carbon$ export CONSUL_HTTP_TOKEN=<management token>
carbon$ consul acl policy create -name unison-cloud -description "Unison Cloud" -rules @/tmp/unison-cloud.hcl
carbon$ consul acl token create -policy-name unison-cloud -description "Unison Cloud"
carbon$ rm /tmp/unison-cloud.hcl
```

The new token's `SecretID`, not its `AccessorID`, goes into `unison_cloud_consul_token`. Never store the management token in agevault. If the policy changes later, update it with `consul acl policy update -name unison-cloud -rules @<file>`. The token keeps working.

### 5. Add the six agevault secrets

From the repo root on cadmium. `write` and `edit` both regenerate `secrets.toml`, which the build needs to see the names.

The two database passwords are random, and only carbon reads them:

```sh
cadmium$ openssl rand -hex 32 | agevault write carbon unison_cloud_api_db_password -
cadmium$ openssl rand -hex 32 | agevault write carbon unison_cloud_nimbus_db_password -
```

The other four are the values from steps 2 to 4. `write` stores the bytes exactly as it gets them, while `edit` opens vi, which adds a trailing newline. So paste each value into a hidden prompt, which keeps it out of your shell history:

```sh
cadmium$ for name in unison_cloud_oidc_client_secret unison_cloud_s3_access_key_id unison_cloud_s3_secret_access_key unison_cloud_consul_token; do
  printf '%s: ' "$name"; read -rs value; echo
  printf '%s' "$value" | agevault write carbon "$name" -
done
cadmium$ unset value
```

In order, it asks for the Pocket ID client secret, the Garage key ID (`GK…`), the Garage secret key, and the Consul `SecretID`.

Push them to carbon's `/usr/lib/credstore.encrypted`:

```sh
cadmium$ agevault push carbon
```

### 6. Deploy

1. Deploy carbon.
2. Deploy gallium and rhodium too. All three serve the `gio.ninja` zone, and only a redeployed server has the `unison`, `api.unison` and `app.unison` records. TLS doesn't depend on this, since Caddy gets its certificates through Cloudflare.
3. Recreate the tmpfiles directories, on the first deploy only. Activation ran tmpfiles before the new dataset was mounted over `/var/lib/unison-cloud`, which hid `log-shipper/`, and Vector exited with `data_dir ... does not exist`. Boots are fine, because `systemd-tmpfiles-setup` runs after `local-fs.target`.

   ```sh
   carbon$ sudo systemd-tmpfiles --create
   carbon$ sudo systemctl restart unison-cloud-log-shipper
   ```

4. Watch the first start:

   ```sh
   carbon$ systemctl list-units 'unison-cloud*'
   carbon$ journalctl -fu unison-cloud-api
   ```

   `unison-cloud-secrets` generates the internal keys into the dataset. `unison-cloud-postgresql-setup` sets the passwords and extensions, `unison-cloud-database` waits for PostgreSQL, and `unison-cloud-migrate` applies the migrations. cloud-api and the nimbus nodes start after those. If one fails, `systemctl status` names it, and the units after it don't start.

## Deploy from ucm

Log ucm in to the cloud once. `auth.login` logs in to whatever `UNISON_SHARE_HOST` points at, so use a separate ucm session for it and do nothing else in that session:

```sh
cadmium$ UNISON_SHARE_HOST=https://api.unison.gio.ninja ucm
```

Run `auth.login`, log in through Pocket ID, and quit. ucm stores credentials per host, so your Share login stays as it is. `jq 'keys' ~/.local/share/unisonlanguage/credentials.json` lists both.

The cloud client reads `UNISON_CLOUD_*` when `Cloud.run` or `Cloud.main` runs. Without them it targets Unison's hosted cloud. So put them in the `.envrc` of each project that deploys to carbon:

```sh
export UNISON_CLOUD_HOST=api.unison.gio.ninja
export UNISON_CLOUD_HTTP_PORT=443
export UNISON_CLOUD_USE_TLS=true
export UNISON_CLOUD_CREDENTIALS_HOST=api.unison.gio.ninja
```

`UNISON_CLOUD_CREDENTIALS_HOST` must match the key `auth.login` stored. Don't set `UNISON_SHARE_HOST` there, so library pulls still go to Share.

Deployed services open under `https://app.unison.gio.ninja/services/…`, and the UI links each one.

## Find the cause of a failure

- **Login says "Your account isn't allowed to log in here":** the `groups` claim doesn't contain `allowedGroups`. cloud-api logs `oidc login refused by the allowlist` with the reason (patch 0012). Check the group's Name and your membership in Pocket ID.
- **Login fails with `selfhost:oidc-upstream-failed`:** the token exchange with Pocket ID failed, and the log line carries Pocket ID's error.
- **A deploy returns 500:** cloud-api usually logs only 200s for it, because nimbus does the work. Check `journalctl -u 'unison-cloud-nimbus-*'` for the same minute.
- **An S3 call fails:** gallium's Garage logs every request at `info`. journalctl's `--since` uses gallium's local time, while carbon logs in UTC, so give the time zone: `journalctl -u garage --since "<date> <time> UTC"`.
- **To test S3 by hand from carbon**, sign a request with the same credentials:

  ```sh
  carbon$ id=$(sudo systemd-creds decrypt /usr/lib/credstore.encrypted/unison_cloud_s3_access_key_id -)
  carbon$ secret=$(sudo systemd-creds decrypt /usr/lib/credstore.encrypted/unison_cloud_s3_secret_access_key -)
  carbon$ curl -sS --http1.1 -I --aws-sigv4 "aws:amz:garage:s3" --user "$id:$secret" https://unison-cloud-services.s3.garage.gio.ninja/<key>
  carbon$ unset id secret
  ```

## Add more nimbus hosts later

This isn't built, but core already supports it. A worker host imports core with `cloudApi.enable = false`, `nimbus.cloudApiHost` set to carbon, and `advertiseAddress` set to its own address. It registers its own nodes with its local Consul agent, so hosts don't coordinate.

What's still open then:

- **Reachability.** cloud-api's ports (24100 to 24102) and the secrets listener (`cloudApi.secretsListenAddress`, loopback by default) must be reachable from the worker, ideally over WireGuard. The worker also needs carbon's PostgreSQL and Loki.
- **The cluster token.** Core generates `cluster-token` on carbon. A second host needs the same one, so it moves to agevault.
- **Firewall.** Core opens nothing, so you open those ports to the worker only.
