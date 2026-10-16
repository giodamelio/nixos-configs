# Run Unison Cloud on carbon

You want your own Unison Cloud on carbon (NIXOS-125). The bottle (`inputs.unison-cloud-in-a-bottle`) now does most of the work for you.

Since 2026-10-16 it exports `nixosModules.core`, a module built for a host like carbon that already runs a reverse proxy, a login provider, PostgreSQL, S3, Consul and Loki. Core runs cloud-api, nimbus and Vector as plain systemd units, sandboxes them, generates its own keys, and hands you the Caddy site bodies. Your job is to point it at what carbon already has.

The earlier version of this plan hand-wrote every unit, along with a private Consul, Redis, ExtendDB and an internal CA. None of that is needed any more:

| Old plan | Now |
|---|---|
| Hand-written cloud-api, nimbus and Vector units | `nixosModules.core` |
| Redis | Gone. Login state lives in PostgreSQL (cloud-api patch 0009) |
| ExtendDB, its setup oneshot, the internal CA and the CA bundle bind-mount | Gone. nimbus stores its data in PostgreSQL (nimbus patches 0003 and 0004) |
| Private single-node Consul | Not needed. cloud-api sends an ACL token and prefixes its keys (patch 0010), so it can join the fleet Consul |
| Header-trust routes to patch out first | Done in the bottle (patch 0008) |
| `_secrets.nix` generating keys | Core generates them in `unison-cloud-secrets` |
| Fleet-wide node list and `worker.nix` | Core's `nimbus.nodes.interactive`. Multi-host is `cloudApi.enable`, `nimbus.cloudApiHost` and `advertiseAddress` |

## What stays the same

- **Domains:** `unison.gio.ninja` (UI), `api.unison.gio.ninja` (API, and `UNISON_CLOUD_HOST` for ucm) and `app.unison.gio.ninja` (deployed services). All three are same-site under gio.ninja, so the session cookie works.
- **Login:** Pocket ID, limited to an `unison-cloud` group.
- **Storage:** Garage on gallium, and carbon's PostgreSQL.
- **Logs:** carbon's existing Loki at `127.0.0.1:3100`.
- **State:** `/var/lib/unison-cloud` (core's default `stateDir`) on its own `bowl/unison-cloud` dataset, backed up.
- **External secrets:** through agevault, snake_case. Core loads each credential under its credstore name, the name agevault encrypts it with (bottle commit `6d514b00`).

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

`modules/aspects/server/unison-cloud/` holds one aspect, `den.aspects.unison-cloud`, included on carbon. import-tree skips the `_` file; `default.nix` imports it.

| File | Contents |
|---|---|
| `default.nix` | Imports `nixosModules.core`, sets `services.unison-cloud`, the `bowl/unison-cloud` dataset, the three endpoints, the backup entry and `den.aspects.carbon.includes` |
| `_postgresql.nix` | The role setup oneshot |

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
    clientId = "<from Pocket ID>";
    # The browser follows the public URL; cloud-api talks to Pocket ID directly.
    endpoints = {
      authorization = "https://login.gio.ninja/authorize";
      token = "http://127.0.0.1:1411/api/oidc/token";
      jwks = "http://127.0.0.1:1411/.well-known/jwks.json";
    };
    allowedGroups = ["unison-cloud"];
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

The S3 defaults already fit Garage: port 443, HTTPS, and virtual-host addressing, which gallium serves through its `*.s3.garage` endpoint. The bucket defaults (`unison-cloud-services` and `unison-cloud-user-blobs`) match what you'll create.

Ports start at 24100 for cloud-api and 24200 for nimbus. Nothing on carbon uses them, and core opens no firewall ports.

## Add the ingress

Each endpoint sets no backend, so `proxy` defaults to false, and uses core's site body instead:

```nix
den.hosts.x86_64-linux.carbon.services.unison-cloud-api.endpoint = {
  domain = "api.unison";
  extraConfig = cfg.caddy.siteConfig.api;
};
```

Do the same for `app.unison` (`siteConfig.apps`) and `unison` (`siteConfig.ui`).

`siteConfig` lives in carbon's NixOS config, while endpoints are declared at the den host level. If the endpoint can't read it from there, the endpoint keeps only `domain` (for DNS) and the aspect sets the vhost's `extraConfig` in its nixos class. I'll find out which works in step 4. The API body already 404s `/internal/*` and strips `X-Auth-Request-*`.

Point the healthcheck at `https://api.unison.gio.ninja/.well-known/openid-configuration`. It needs no login, and a 200 means Caddy and cloud-api are up.

## Set up PostgreSQL

`_postgresql.nix` adds a oneshot that runs as `postgres` before `unison-cloud-database.service`. It loads the two password credentials and runs SQL like the battery's own setup:

- `unison_cloud`, which owns database `unison_cloud`, with `uuid-ossp`, `citext` and `moddatetime`;
- `unison_cloud_nimbus`, which owns database `unison_cloud_nimbus`;
- `REVOKE ALL ... FROM PUBLIC` on both, so neither role reads the other's tables.

Both roles log in over `127.0.0.1` with a password, which NixOS's default `host all all 127.0.0.1/32` rule already allows.

## Work through it in order

1. **Bottle:** the credential-name fix landed in `6d514b00`, and the lock points at it. Wait for its CI run to push to Cachix before building.
2. **Scaffold:** the aspect, the dataset and the backup entry, with `services.unison-cloud` set. Eval it.
3. **PostgreSQL:** the role setup oneshot.
4. **Ingress:** the three endpoints and the healthcheck.
5. **Test:** the VM test, then `prek run -a` and a toplevel build. Then I hand over to you to deploy.

Each step is a separate jj change. I `git add` new files as I create them.

## Do these steps by hand

I'll print the exact commands for each.

1. **Create the dataset:** `zfs create -o mountpoint=legacy -o atime=off bowl/unison-cloud` on carbon.
2. **Set up Garage:** create the buckets `unison-cloud-services` and `unison-cloud-user-blobs`, plus a key limited to them.
3. **Set up Pocket ID:**
   - Create a confidential client with the redirect URI `https://api.unison.gio.ninja/selfhost/oidc/callback`.
   - Create an `unison-cloud` group with you in it.
   - Give me the client ID; it goes inline in `default.nix`.
4. **Create the Consul token:** with a management token, build the policy and create a token from it:

   ```sh
   policy=$(nix build --no-link --print-out-paths .#nixosConfigurations.carbon.config.services.unison-cloud.consul.aclPolicy)
   consul acl policy create -name unison-cloud -rules @"$policy"
   consul acl token create -policy-name unison-cloud -description "Unison Cloud"
   ```

5. **Add the six agevault secrets:** `unison_cloud_oidc_client_secret`, `unison_cloud_s3_access_key_id`, `unison_cloud_s3_secret_access_key`, `unison_cloud_api_db_password` and `unison_cloud_nimbus_db_password` (both `openssl rand -hex 32`), and `unison_cloud_consul_token` (the token's secret ID). Then regenerate `secrets.toml`.

## Verify it

- Run `prek run -a`, then `nom build .#nixosConfigurations.carbon.config.system.build.toplevel`. Don't build until the bottle's Cachix has the locked commit.
- Add a `perSystem.denTests.unison-cloud` VM test, following `modules/checks/heartbeat.nix`. The bottle's `tests/shared-host.nix` already covers a core-only host, so this one only checks carbon's wiring:
  - every `unison-cloud-*` unit reaches active;
  - `/.well-known/openid-configuration` returns 200 through Caddy;
  - Vector's user lines land in Loki under `job="nomad_allocs"`.
- After you deploy carbon:
  - check `systemctl list-units 'unison-cloud*'`;
  - log in at `https://unison.gio.ninja` through Pocket ID;
  - run `UNISON_CLOUD_HOST=api.unison.gio.ninja ucm`, then `auth.login`;
  - deploy a hello service and open it under `https://app.unison.gio.ninja/services/…`;
  - check its logs show up in the UI and in Grafana.

## Add more nimbus hosts later

This isn't built now, but core already supports it. A worker host imports core with `cloudApi.enable = false`, `nimbus.cloudApiHost` set to carbon, and `advertiseAddress` set to its own address. It registers its own nodes with its local Consul agent, so hosts don't coordinate.

What's still open then:

- **Reachability.** cloud-api's ports (24100 to 24102) and the secrets listener (`cloudApi.secretsListenAddress`, loopback by default) must be reachable from the worker, ideally over WireGuard. The worker also needs carbon's PostgreSQL and Loki.
- **The cluster token.** Core generates `cluster-token` on carbon. A second host needs the same one, so it moves to agevault.
- **Firewall.** Core opens nothing, so you open those ports to the worker only.
