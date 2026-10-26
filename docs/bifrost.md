# Expose services to the internet through bifrost

bifrost is the single place where internet traffic enters your LAN. It runs as a Caddy plugin in its own Caddy instance on carbon. It checks every request before it reaches a target: webhook signatures, static bearer tokens, or OAuth access tokens it issued itself. Then it proxies the request with ordinary Caddy rules.

It also works as an OAuth authorization server, so MCP servers (yours in Unison, Go or anything else, or someone else's) can be exposed with real auth without implementing any of it. You approve each client by logging in to Pocket ID, which only works from the LAN or VPN.

bifrost replaces webhookcatcher (`modules/hosts/carbon/_staged/hooks.nix`). The work is tracked in NIXOS-128, with one subtask per build stage.

## Know the shape of it

- **Public names:** `*.external.gio.ninja`. One subdomain per service. `auth.external.gio.ninja` is bifrost's own authorization server and admin page.
- **Entry point:** the gateway forwards public 443 to carbon:52793. Nothing else that is HTTP or HTTPS is forwarded, now or later.
- **Process:** a dedicated Caddy instance, separate from the internal reverse proxy, built with the bifrost plugin, caddy-ratelimit and the Cloudflare DNS provider.
- **Login:** Pocket ID at `login.gio.ninja`, which stays LAN-only. A fresh login is required for every new authorization.
- **State:** `ctx.Storage()` (Caddy's built-in certmagic storage) plus memory. No database.
- **Identity to targets:** a short-lived signed JWT in `X-Bifrost-Assertion`, verifiable against a standard JWKS.
- **Abuse limits:** caddy-ratelimit inside Caddy, and fail2ban on carbon banning at nftables.
- **Language:** Go, with [ory/fosite](https://github.com/ory/fosite) for the OAuth server.

## Decisions

You confirmed these on 2026-10-25:

- **Name:** bifrost.
- **Form:** a Caddy plugin in Go, built on fosite, not a standalone binary.
- **Source:** a directory in this repo, built with `buildGoModule`.
- **One subdomain per service.** A service gets everything under its subdomain. Path rewrites to a target's sub-path use normal Caddy `rewrite`.
- **Banning:** fail2ban on carbon. Not CrowdSec, and not on the gateway.
- **Rate limiting:** [mholt/caddy-ratelimit](https://github.com/mholt/caddy-ratelimit).
- **No client IP headers from the internet.** The port forward preserves the real source address. The only trusted proxy is loopback, which is how LAN traffic arrives (see [Reach bifrost from the LAN](#reach-bifrost-from-the-lan)).
- **Fresh login:** `prompt=login` on every authorization, enforced by checking `auth_time`.
- **No client allowlist.** The consent screen shows the client and its redirect host prominently instead.
- **Tokens:** opaque access tokens with real revocation, not self-contained JWTs.
- **Storage:** `ctx.Storage()` with a `version` field in every blob. No migrations framework, no extra database to back up.
- **Client ID metadata documents:** fetched and cached in memory.
- **Authorization codes and login state:** in memory.
- **Admin page:** at `auth.external.gio.ninja/admin`, listing grants with usage stats and revoke buttons.
- **Identity:** a signed assertion JWT. bifrost generates its own signing keys, stores them in `ctx.Storage()` and rotates them.
- **Third-party targets:** you map identity into their headers by hand with `header_up`.
- **API-style sessions only.** No browser-session checker for proxied web apps.
- **No `forward_auth` endpoint yet.** Add it when something needs it.
- **Internal DNS:** a wildcard `*.external` record pointing at carbon.
- **Public DNS:** caddy-dynamicdns in the edge instance keeps `external.gio.ninja` current, reusing `caddy_cloudflare_api_token`. You create the `*.external` CNAME by hand.
- **Port:** carbon:52793, behind the public 443 forward.
- **Lifetimes:** access token 30 minutes, refresh token 30 days from last use, assertion 2 minutes, signing key rotation 30 days.
- **Pocket ID:** assume the deployed version honors `prompt=login` and returns `auth_time`. It's very recent. Fix it if stage 2 shows otherwise.
- **Instance:** the unit is `caddy-bifrost.service` (the `gio.caddy` wrapper names every instance `caddy-<name>`), running as the `bifrost` user, with state on a backed-up `bowl/bifrost` dataset at `/var/lib/bifrost`.
- **Abuse defaults:** set well above any legitimate workload, to stop spamming bots. Webhook routes aren't exempt from bans.

## Route traffic into the LAN

### Set up DNS

| Where | Record | Points at |
|---|---|---|
| Cloudflare | `external.gio.ninja` A | Your public IPv4, kept current by caddy-dynamicdns |
| Cloudflare | `*.external.gio.ninja` CNAME | `external.gio.ninja` |
| Fleet CoreDNS | `*.external.gio.ninja` CNAME | `carbon.gio.ninja` |

Only one name changes. The edge instance keeps it current with [mholt/caddy-dynamicdns](https://github.com/mholt/caddy-dynamicdns), a Caddy app compiled into the same binary. It reuses the Cloudflare DNS provider and token already there for ACME:

```caddyfile
dynamic_dns {
	provider cloudflare {file./run/credentials/caddy-bifrost.service/caddy_cloudflare_api_token}
	domains {
		gio.ninja external
	}
	versions ipv4
}
```

`versions ipv4` keeps it from publishing an AAAA record, because the Webpass IPv6 prefix doesn't route back. This removes the question of whether UniFi's built-in DDNS can update Cloudflare.

The wildcard CNAME never changes. Create it once by hand in Cloudflare, and move it into terranix when NIXOS-24 lands, alongside the UniFi port forward that task already mentions.

The token is `caddy_cloudflare_api_token`, the one the internal Caddy already uses for ACME. Its scope has to cover editing DNS records on `gio.ninja`, which DNS-01 already requires.

The internal record matters for the login flow. Your browser has to reach `auth.external.gio.ninja` during login. Without the internal record, CoreDNS falls through to 1.1.1.1 (`modules/aspects/dns/server.nix:47`) and returns the public IP, so LAN traffic hairpins through the gateway. Hairpinned traffic may arrive with the gateway's address as its source. That breaks per-IP rate limiting, can get the gateway banned, and defeats the `remote_ip` guard on `/admin`.

In Nix that is `fleet.dns.zones."gio.ninja".subdomains."*.external".CNAME = ["carbon.gio.ninja."]` in `modules/hosts/carbon/bifrost.nix`. The `fleet-dns` check now covers a wildcard CNAME.

### Reach bifrost from the LAN

The internal record sends LAN clients to carbon on port 443, the internal Caddy, not bifrost's 52793. So `gio.bifrost.lanProxy` (on by default) gives the internal Caddy one more site, `*.external.gio.ninja`, that proxies to `https://127.0.0.1:52793` with SNI `auth.external.gio.ninja`, verifying bifrost's real certificate.

The internal Caddy sets `X-Forwarded-For` to the LAN client's address; it has no trusted proxies itself, so it never passes a client's own header through. bifrost trusts `X-Forwarded-For` only from loopback:

```caddyfile
servers {
	trusted_proxies static 127.0.0.1/32 ::1/128
	client_ip_headers X-Forwarded-For
}
```

Internet clients can't connect from loopback, so they can't spoof it. Everything address-based in bifrost uses the client IP this produces: rate-limit keys are `{client_ip}` rather than `{remote_host}`, and the failure log, fail2ban, `admin_networks` and the grant's last IP all see the real LAN address.

### Forward one port

The gateway forwards public TCP 443 to carbon:52793. carbon's firewall opens 52793 to any source, because internet clients arrive with their own addresses. The gateway decides what gets in; the source address is the client's.

Certificates come from ACME DNS-01 through Cloudflare as a single wildcard for `*.external.gio.ninja`. Nothing else needs forwarding. `auto_https disable_redirects` keeps the instance off port 80.

### Reject everything unknown

Any host or path that no route matches hits `bifrost_reject`. It returns 404 and logs the request as a failure, so scanners feed fail2ban.

## Authenticate MCP and API clients

### Follow the flow

1. A client (claude.ai's backend, Claude Code, any OAuth-capable API client) calls `https://notes.external.gio.ninja/...` with no token.
2. The `oauth` guard answers 401 with `WWW-Authenticate: Bearer resource_metadata="https://notes.external.gio.ninja/.well-known/oauth-protected-resource", scope="..."`.
3. The client fetches that metadata. It names `https://auth.external.gio.ninja` as the authorization server.
4. The client fetches `https://auth.external.gio.ninja/.well-known/oauth-authorization-server` and either uses a client ID metadata document or registers itself.
5. The client sends your browser to `/authorize` with PKCE, `state` and `resource=https://notes.external.gio.ninja`.
6. bifrost redirects your browser to Pocket ID with `prompt=login`. This only works from the LAN or VPN.
7. You authenticate with a passkey. Pocket ID redirects back to `https://auth.external.gio.ninja/callback`.
8. bifrost checks that the ID token's `auth_time` is no more than five minutes old, then shows the consent screen.
9. You approve. bifrost creates a grant, issues a code and redirects your browser to the client's redirect URI.
10. The client exchanges the code at `/token` (public, server to server) for an access token and a refresh token, both bound to `https://notes.external.gio.ninja`.
11. The client calls the service with `Authorization: Bearer ...`. The guard validates the token, strips it, adds the assertion and proxies to the target.

The client only ever talks to `*.external`. Only your browser touches `login.gio.ninja`.

### Keep the gate where it is

The real control is that Pocket ID can't be reached from the internet. Never add `login` to public DNS or the port forward.

Don't add source-IP checks to the authorization flow as a second gate. The redirect-based flow passes through the browser, so the edge can't reliably tell where the person is. The `/admin` page is the one exception, covered below.

### Force a fresh login

bifrost always sends `prompt=login` to Pocket ID. Pocket ID's source honors it (`backend/internal/oidc/authorization_service.go`, along with `max_age` and a per-client re-authentication setting). bifrost doesn't rely on that: it rejects any ID token whose `auth_time` is older than `max_auth_age`.

A login only happens for a new authorization. Refresh tokens keep existing grants working, so this doesn't add friction day to day.

Configure bifrost's Pocket ID client:
- redirect URI `https://auth.external.gio.ninja/callback`;
- allowed group `bifrost`, so only accounts you choose can approve anything.

### Show the consent screen loudly

Every authorization shows a consent screen after login. There's no allowlist, so the screen has to carry the weight:

- The **redirect URI host**, large and first. This is where the code goes, and the main anti-phishing signal.
- The client name and `client_id`. For a client ID metadata document, also the host serving the document.
- The resource being granted and the scopes requested.
- A warning when every redirect URI is loopback. The MCP spec calls this out: a malicious local process can claim any client's metadata document and listen on a loopback port.

### Register clients

bifrost advertises both mechanisms the MCP spec describes.

**Client ID metadata documents** (`client_id_metadata_document_supported: true`) come first. The `client_id` is an HTTPS URL. bifrost fetches it, validates that `client_id` matches the URL exactly, checks the redirect URI against `redirect_uris`, and caches the result in memory, respecting HTTP cache headers.

The fetch is an SSRF risk, so it:
- requires HTTPS;
- refuses private, loopback and link-local destinations after DNS resolution;
- caps the response size;
- uses a short timeout.

**Dynamic client registration** (RFC 7591) at `/register` is the fallback for older clients. Registrations persist in storage.

### Bind tokens to one service

The MCP spec requires clients to send RFC 8707 `resource` on both the authorize and token requests, and requires servers to reject tokens issued for anyone else.

fosite has no RFC 8707 support of its own, but it fully supports audiences. bifrost bridges the two:

1. The authorize and token handlers read the repeatable `resource` parameter.
2. Each value must be a registered resource (see [Register resources from guards](#register-resources-from-guards)). Anything else is `invalid_target`.
3. The values become fosite's requested audience and are granted after consent.
4. Every client's allowed audience is the current set of registered resources.
5. The `oauth` checker requires its own resource URI in the token's audience.

The canonical resource URI is `https://<subdomain>.external.gio.ninja`, with no path or trailing slash. One subdomain per service makes that unambiguous.

fosite's `DefaultAudienceMatchingStrategy` (`audience_strategy.go`) already treats audiences as URIs. It requires an equal scheme and host, and an equal path or a path under the allowed one, so `https://notes.external.gio.ninja` works as-is with no custom strategy. Two details sit in bifrost's bridge, not in fosite:
- It lowercases the scheme and host first. fosite compares the host as-is, and the MCP spec says to accept uppercase.
- It checks `resource` against the registry exactly, so fosite's path-prefix leniency never comes into play.

### Meet the rest of OAuth 2.1

- PKCE with `S256` is required for every client. `code_challenge_methods_supported` is advertised, without which MCP clients refuse to proceed.
- Refresh tokens rotate on every use, which the spec requires for public clients. Reusing a rotated refresh token revokes the whole grant.
- Redirect URIs must match exactly and be HTTPS or loopback.
- Lifetimes: access token 30 minutes, refresh token 30 days from last use.

### Serve these endpoints on auth.external.gio.ninja

| Path | Purpose |
|---|---|
| `/.well-known/oauth-authorization-server` | RFC 8414 metadata |
| `/.well-known/jwks.json` | Public keys for assertions |
| `/authorize` | Starts the flow, redirects to Pocket ID |
| `/callback` | Pocket ID's return, then the consent screen |
| `/consent` | Consent form POST |
| `/token` | Code and refresh exchange |
| `/register` | Dynamic client registration |
| `/revoke` | RFC 7009 revocation for clients |
| `/admin` | Grant list, stats and revocation (LAN only) |

## Check requests per route

### Pick a checker

`bifrost_guard` runs one checker per route. Checkers are Caddy guest modules in the `bifrost.checkers` namespace, so new types are new modules.

| Checker | Verifies | Config |
|---|---|---|
| `oauth` | A bifrost access token for this subdomain, with the required scopes | `scopes` |
| `hmac` | A body signature, GitHub style or timestamped | `header`, `prefix`, `algorithm`, `secret_file`, optional `timestamp_header` and `tolerance` |
| `bearer` | A static token, compared in constant time | `token_file` |

Routes are plain Caddy, so any matcher can choose what a guard covers: host, path, method, headers, `remote_ip` or a CEL expression. Inside one service's subdomain, different paths can carry different checkers, for example `hmac` on `/hooks/github/*` and `oauth` on everything else.

The `hmac` checker buffers the body, with a size cap, to verify it, then hands it on unchanged. For GitHub-style signatures with no timestamp, it can deduplicate the delivery ID header in memory to blunt replays.

### Handle headers on every request

On every request, before checking, the guard deletes any incoming `X-Bifrost-*` header.

When the `oauth` check passes, the guard also:
- removes `Authorization` (the MCP spec forbids passing the token through);
- sets `X-Bifrost-Assertion`;
- exposes `{vars.bifrost_user}`, `{vars.bifrost_sub}`, `{vars.bifrost_email}`, `{vars.bifrost_name}`, `{vars.bifrost_client_id}`, `{vars.bifrost_client_name}`, `{vars.bifrost_scopes}` and `{vars.bifrost_grant_id}` for `header_up`. They use underscores because the Caddyfile's `{vars.*}` shorthand doesn't match dots.

The `hmac` and `bearer` checkers leave `Authorization` alone and add no identity, because there's no user.

### Answer OAuth discovery from the guard

The `oauth` guard answers any `/.well-known/oauth-protected-resource*` path on its host itself. Clients probe both the root and the path-inserted variant, and both get the same RFC 9728 document: `resource`, `authorization_servers` and `scopes_supported`.

Failures follow the spec:
- **Missing, invalid or expired token:** 401 with `resource_metadata` and `scope`.
- **Insufficient scope:** 403 with `error="insufficient_scope"`.

### Register resources from guards

You declare a resource only once, in its guard. During provisioning, each `oauth` guard gets the `bifrost` app with `ctx.App("bifrost")` and registers its subdomain as a resource with its scopes. The authorization server validates `resource` against that registry.

A config reload builds a new app and a new registry, so the list can't go stale. The guard learns its subdomain from config, not from the request, so a forged `Host` can't register anything. Each guard names its host explicitly, or the Nix wrapper fills it in.

## Tell targets who is calling

### Send a signed assertion

On a passing `oauth` check, bifrost adds `X-Bifrost-Assertion`, a JWT (RFC 7519) signed with EdDSA/Ed25519 (RFC 8037):

| Claim | Value |
|---|---|
| `iss` | `https://auth.external.gio.ninja` |
| `aud` | The service's resource URI, so it's useless against any other target |
| `sub` | Pocket ID subject |
| `email`, `name` | From Pocket ID |
| `client_id`, `client_name` | The OAuth client |
| `scope` | Granted scopes |
| `grant_id` | The grant, matching the admin page |
| `iat`, `exp` | Two-minute lifetime |
| header `kid` | The signing key |

A target that ignores the header needs nothing. A target that wants identity verifies the JWT against `https://auth.external.gio.ninja/.well-known/jwks.json` (RFC 7517) and checks `aud` and `exp`. A forged header fails no matter how the request reached the target. So there are no firewall rules, socket permissions or Nix plumbing between bifrost and its targets, and targets can be on any host and written by anyone.

Verifiers cache the JWKS and refetch only on an unknown `kid` or when the cache expires. In Go:
- `lestrrat-go/jwx` has `jwk.Cache`;
- `MicahParks/keyfunc` covers `golang-jwt`.

Apps that already support Cloudflare Access-style JWT headers can be pointed at the header and the JWKS URL directly.

The leftover risk is replay. For two minutes, anyone who sees an assertion (the target, or someone sniffing a plain-HTTP hop to another host) can replay it against that same target. On your LAN that's acceptable.

### Rotate signing keys automatically

bifrost generates its own Ed25519 keys and keeps them in `ctx.Storage()`. There's no secret to provision.

- The JWKS publishes the current key and the next one, so verifiers already have the next key cached before it's used.
- Every rotation period (proposed 30 days), the next key becomes current and a new next key is generated.
- The retired key stays published until every assertion it signed has expired, which is two minutes.
- Rotation happens under a mutex in the key ring, which lives in the `UsagePool` entry that overlapping instances share during a reload, so they can't both rotate.

### Map headers by hand for third-party targets

For a target that expects plain identity headers, map them yourself:

```caddyfile
reverse_proxy 10.0.0.50:8080 {
	header_up X-Forwarded-User {vars.bifrost_user}
	header_up X-Forwarded-Email {vars.bifrost_email}
}
```

Plain headers are only as trustworthy as the network path to that target. That's your call per route.

## Store state without a database

`ctx.Storage()` is a key-value store with locks: Store, Load, Delete, Exists, List, Stat, Lock and Unlock. It's file-backed by default, in the instance's data directory next to its certificates. At one user it holds a handful of small JSON files.

| Data | Where | Lifetime |
|---|---|---|
| Grants (user, client, resource, scopes, created, stats) | `bifrost/grants/<grant_id>.json` | Until revoked or refresh expiry |
| Access tokens, keyed by HMAC signature | `bifrost/access/<signature>.json` | 30 minutes |
| Refresh tokens, keyed by HMAC signature | `bifrost/refresh/<signature>.json` | 30 days from last use |
| Registered clients | `bifrost/clients/<client_id>.json` | Until deleted on the admin page |
| Signing keys | `bifrost/keys/<kid>.json` | Until retired and expired |
| Client ID metadata documents | Memory | HTTP cache headers |
| Authorization codes, PKCE, login and consent state | Memory | Minutes |
| Usage counters | Memory, flushed into grants about every minute | |
| Rate limits and in-flight dedup | Memory | |

Every stored blob carries `"version": 1`. A new version gets a reader for the old shape. There's no migrations framework.

A grant is a fosite request ID. Every access and refresh token from one authorization, including rotated refresh tokens, is tied to it. The grant file lists its live token signatures, which is the index fosite's revoke-by-request needs. Revoking a grant deletes the grant file and every token it lists. Since access tokens are looked up on every request, revocation takes effect immediately.

An in-memory index loaded at start keeps lookups off disk. Writes go to storage first, then memory. A sweeper deletes expired token files hourly.

Caddy starts new module instances before stopping old ones on a reload. Shared in-process state therefore lives in a `caddy.UsagePool`: the memory index, the mutex used for refresh-token rotation, and the counters. Old and new instances share it, and it survives the reload.

Losing storage means every client re-authorizes. Nothing worse.

Two secrets come from systemd credentials through agevault:
- `bifrost_token_key`: fosite's HMAC key for opaque tokens. A forged token fails before any lookup, and storage holds only signatures, which can't be turned back into tokens. HKDF subkeys derived from it sign the admin session cookie and the login state cookie.
- `bifrost_pocket_id_client_secret`: the Pocket ID client secret.

## Revoke grants from the admin page

`/admin` on `auth.external.gio.ninja` lists every grant:
- user, client name, `client_id`, and redirect host;
- resource and scopes;
- created time, last used time, last client IP and request count.

It also shows per-service request counts and recent failures. Each grant has a revoke button. Registered clients are listed with a delete button that also revokes their grants.

Two locks protect it:
- **A `remote_ip` matcher** limited to LAN and VPN ranges, which the internal DNS record makes reliable.
- **A bifrost session cookie** from a Pocket ID login, also with `prompt=login` and the `bifrost` group.

Revokes and deletes are POSTs with CSRF tokens.

## Limit abuse

### Rate limit with caddy-ratelimit

Zones are keyed on `{client_ip}`, the real client address for internet and LAN traffic alike. The defaults sit well above any legitimate workload. They exist to stop bots, not to shape your own traffic:

| Zone | Applies to | Limit |
|---|---|---|
| `auth` | `/authorize`, `/token`, `/register`, `/callback` | 60 per minute |
| `admin` | `/admin` | 120 per minute |
| per service | Each service's routes | 1200 per minute, overridable per route |

Caddy returns 429 when a limit is exceeded. Long-lived SSE streams count as one event each, not per byte.

### Ban with fail2ban

Every failed check logs one structured line from the `bifrost` logger: bad signature, bad or expired token, unknown client, rejected host. It includes the client address, the route and the reason.

NixOS `services.fail2ban` on carbon:
- reads the edge instance's journal (`backend = systemd`, matched on the unit);
- matches those lines;
- bans with the nftables action on port 52793 only.

Starting defaults: 50 failures within 10 minutes bans the address for 1 hour. A real client with a stale token fails once and re-authorizes, and a misconfigured webhook sender retries a handful of times. Only something spamming crosses 50.

Only LAN and VPN ranges are exempt, via `ignoreip`. Webhook routes count like everything else. GitHub's hook IPs are shared, so a ban could drop real deliveries for an hour. The high threshold makes that unlikely, and GitHub redelivers. Revisit this if it ever happens.

## Proxy MCP over Streamable HTTP

Streamable HTTP passes through `reverse_proxy`. Caddy flushes `text/event-stream` responses immediately, and `Mcp-Session-Id`, GET streams and DELETE pass through untouched.

- **Set `stream_close_delay`** (proposed `10m`) on MCP routes. By default Caddy closes streaming connections when a config is unloaded, so every deploy would cut open SSE streams.
- **Rewriting a target path is fine for APIs and MCP.** `rewrite * /mcp{uri}` maps the subdomain root onto a target's `/mcp`. Links a target puts in its response bodies won't be rewritten, so mount page-rendering targets at their root. The guard runs before the rewrite, so discovery still answers at the subdomain root.
- **The legacy HTTP+SSE transport** (2024-11-05) sends the client an endpoint URL. It only works if the target's path is the public path, without a rewrite.
- **Targets with their own OAuth** must run with it disabled. bifrost is the authorization server.

## Lay out the plugin

| Module ID | Caddyfile | Role |
|---|---|---|
| `bifrost` (app) | global option `bifrost { }` | Owns fosite, the Pocket ID client, storage access, the resource registry, signing keys and counters |
| `http.handlers.bifrost_authserver` | `bifrost_authserver` | The endpoints on `auth.external` |
| `http.handlers.bifrost_guard` | `bifrost_guard <checker> { }` | Header stripping, the checker, identity, failure logging |
| `http.handlers.bifrost_reject` | `bifrost_reject` | Catch-all 404 that logs a failure |
| `bifrost.checkers.oauth` | `oauth` | OAuth token checker |
| `bifrost.checkers.hmac` | `hmac` | Body signature checker |
| `bifrost.checkers.bearer` | `bearer` | Static token checker |

Each module implements the Caddy lifecycle:
- `Provision` loads guest checkers via `ctx.LoadModule` with `inline_key` `type`, gets the app via `ctx.AppIfConfigured`, and registers resources. It also reads every secret file, so a missing credential fails the config load instead of the first request.
- `Cleanup` releases `UsagePool` references. When the last instance releases the shared state, it stops the background loop and flushes counters.
- Login discovery against Pocket ID is lazy, so a Pocket ID outage only breaks logins, never webhook routes or token checks.

`UnmarshalCaddyfile` gives every module Caddyfile syntax.

The app holds no state outside storage and the `UsagePool`, so overlapping instances during a reload are safe.

## Configure a site

You expose a service with one entry in `gio.bifrost.services`. The attribute name is the subdomain, and `config` is ordinary Caddyfile that runs inside the service's `route` after its rate limit:

```nix
gio.bifrost = {
  credentials = ["notes_github_webhook_secret"];

  services = {
    # An MCP server: `oauth` generates the guard, with host filled in.
    notes = {
      oauth = {
        scopes = ["notes:read" "notes:write"];
        require = ["notes:read"];
      };
      config = ''
        rewrite * /mcp{uri}
        reverse_proxy gallium.gio.ninja:9200 {
          stream_close_delay 10m
          header_up X-Forwarded-User {vars.bifrost_user}
        }
      '';
    };

    # A webhook: write the guard yourself, reading credentials from credentialDir.
    notes-hooks.config = ''
      bifrost_guard hmac {
        header X-Hub-Signature-256
        prefix sha256=
        secret_file ${config.gio.bifrost.credentialDir}/notes_github_webhook_secret
      }
      reverse_proxy gallium.gio.ninja:9201
    '';
  };
};
```

The aspect turns that into the instance's Caddyfile:
- a global block with `auto_https disable_redirects`, the loopback trusted proxy, the `bifrost` app and `dynamic_dns`;
- one `*.external.gio.ninja` site with the wildcard certificate;
- the `auth` host with the `admin` and `auth` rate-limit zones and `bifrost_authserver`;
- one `handle` per service, each with its own `rate_limit` zone (default 1200 per minute, `rateLimit` per service);
- `bifrost_reject` as the catch-all.

Every guard is inside a `route`, so the order is always rate limit, guard, then your handlers. `auth` is reserved; an assertion rejects it as a service name. The package's VM test (`modules/packages/bifrost/_test.nix`) carries a complete hand-written Caddyfile if you want to see one.

## Wire it into the repo

| File | Contents |
|---|---|
| `modules/packages/bifrost/` | The Go module: the plugin, `cmd/caddy/main.go`, Go tests and templates |
| `modules/packages/bifrost/bifrost.nix` | `packages.bifrost` (`buildGoModule`, runs the Go tests) and `checks.bifrost-vm` |
| `modules/packages/bifrost/_test.nix` | The package's VM test: real HTTPS, fake Pocket ID, full OAuth flow, admin revoke, rate limit |
| `modules/aspects/server/bifrost.nix` | `den.aspects.bifrost`: the `gio.bifrost` options, the Caddy instance, credentials, firewall, fail2ban, the LAN proxy |
| `modules/checks/bifrost.nix` | The aspect's den VM test: systemd-creds delivery, generated config, a fail2ban ban |
| `modules/hosts/carbon/bifrost.nix` | carbon: includes the aspect, the Pocket ID client ID, `bowl/bifrost`, the backup entry, the internal wildcard record |
| `modules/hosts/carbon/_staged/bifrost-hooks.nix` | The Gradient webhook routes, staged with Gradient |

- **The binary:** `cmd/caddy/main.go` is what xcaddy would generate: Caddy's standard modules, caddy-ratelimit, caddy-dynamicdns, the Cloudflare DNS provider and bifrost. Versions are pinned in `go.mod` under one `vendorHash`, so `withPlugins` isn't needed. The `src` is a fileset of the Go files, `go.mod`, `go.sum` and `templates/`, so editing the `.nix` file doesn't rebuild Caddy.
- **No ACME server module.** `main.go` lists `modules/standard` by hand without `caddypki/acmeserver`. bifrost never runs an ACME server, and that module's badger dependency can't build alongside fosite (next point).
- **fosite is pinned at v0.47.0.** fosite v0.48 and later need the generic `ristretto` v1, while Caddy's PKI (through smallstep's badger) needs the pre-generic v0.2. One module path can't be at both versions in one binary, and `caddytls` needs `caddypki`, so v0.47.0 is the newest fosite that builds into Caddy. Its storage interfaces differ slightly (no access signature on refresh tokens, `RevokeRefreshTokenMaybeGracePeriod` instead of `RotateRefreshToken`); compile-time assertions in `app.go` catch any mismatch, because `compose.Compose` only type-asserts storage at runtime. Revisit when smallstep drops badger or Caddy moves PKI off it.
- **Development:** `pkgs.go` is already in the devshell. Run the Go tests with `go test ./...` in `modules/packages/bifrost`.
- **Instance:** `gio.caddy.instances.bifrost`, so `caddy-bifrost.service`, running as the static `bifrost` user (not a DynamicUser, whose private state directory can't sit on a mounted dataset). Credentials load with `LoadCredentialEncrypted` and appear in `/run/credentials/caddy-bifrost.service/`:
  - `bifrost_token_key`
  - `bifrost_pocket_id_client_secret`
  - `caddy_cloudflare_api_token`, the same token the internal Caddy uses
  - anything in `gio.bifrost.credentials`
- **Pocket ID:** a `bifrost` OIDC client and a `bifrost` group.
- **Backups:** carbon's root dataset isn't backed up, so `/var/lib/bifrost` is its own `bowl/bifrost` dataset, declared in disko and listed in `fleet.backups.zfs.carbon`. disko doesn't add datasets to an existing pool on deploy, so you create it on carbon by hand once.
- **fail2ban on carbon:** enabling it also brings NixOS's default `sshd` jail and sets sshd's `LogLevel` to `VERBOSE`. The LAN and VPN are in `ignoreIP`, so it can't lock you out.

## Replace webhookcatcher

webhookcatcher verified the Gradient GitHub App webhook (HMAC) and the Gradient deploy webhooks (token) on `hooks.gio.ninja:47291`. Both become bifrost routes on their own `*.external` subdomains, reusing the same two secrets:
- `gradient_github_app_webhook_secret`
- `gradient_action_deploy_webhook_token`

The routes are in `modules/hosts/carbon/_staged/bifrost-hooks.nix`, waiting with Gradient and Restate, which they proxy to:

| Route | Check | Target |
|---|---|---|
| `https://gradient-hooks.external.gio.ninja/` | `hmac`, `X-Hub-Signature-256` | gradient-server `127.0.0.1:3002/api/v1/hooks/github` |
| `https://deploy-hooks.external.gio.ninja/<app>` | `bearer` | Restate `/gradient-deployer-carbon/<app>/Reconcile`, for `yesman` and `eater-of-feeds` |

The staged `gradient.nix` deploy actions already point at the new URLs. When Gradient comes back, move `bifrost-hooks.nix` out of `_staged/` and change the GitHub App's webhook URL to `https://gradient-hooks.external.gio.ninja/`. Delete `_staged/hooks.nix` and the `webhookcatcher` package in a later pass.

## Build it in stages

1. **Edge and webhooks:**
   - the edge instance, DNS, port forward and wildcard certificate;
   - `bifrost_guard` with the `hmac` and `bearer` checkers, and `bifrost_reject`;
   - rate limiting and the fail2ban jail.

   This reaches webhookcatcher parity. Verify by sending signed and unsigned test deliveries from outside the LAN, and by checking that repeated failures produce a ban.
2. **Authorization server:**
   - the `bifrost` app with fosite, storage, the Pocket ID login, consent, client registration, resource indicators and refresh rotation;
   - the `oauth` checker;
   - assertions and the JWKS with key rotation.

   Verify with Claude Code and claude.ai connecting to a test MCP server, a target verifying the assertion, and a revoked grant failing on the very next request.
3. **Admin page:** grants, clients, stats, revocation.

## Publish requests to NATS (stretch goal)

Tracked in NIXOS-132. Start it only after the three stages land, in a new commit.

A `bifrost_nats` terminal handler replaces `reverse_proxy` on a route. Once the guard passes, it publishes the whole request to NATS as one JSON message and answers `202 Accepted`. A webhook then needs no HTTP target at all: a consumer subscribes and processes it on its own schedule.

```caddyfile
@github host github-hooks.external.gio.ninja
handle @github {
	route {
		bifrost_guard hmac {
			header X-Hub-Signature-256
			prefix sha256=
			secret_file /run/credentials/caddy-bifrost.service/github_webhook_secret
		}
		bifrost_nats {
			subject bifrost.requests.github
		}
	}
}
```

The message is versioned JSON:

```json
{
  "version": 1,
  "received_at": "2026-10-26T18:04:05Z",
  "method": "POST",
  "host": "github-hooks.external.gio.ninja",
  "path": "/",
  "query": {},
  "headers": {"X-GitHub-Event": ["push"]},
  "remote_ip": "140.82.115.1",
  "body": "{\"ref\":\"refs/heads/main\"}",
  "body_encoding": "utf-8",
  "identity": null
}
```

- **Body:** sent as text when it is valid UTF-8; otherwise base64, with `body_encoding: "base64"`.
- **Identity:** filled in when the route's guard is `oauth`, using the same fields as the assertion.
- **Connection:** one NATS connection shared across reloads through the app's usage pool, authenticated with a credential.
- **Failures:** if the publish fails, the handler answers `503` so the sender retries. It never drops a request silently.
- **Durability:** optionally publish through JetStream and wait for the ack before answering.
