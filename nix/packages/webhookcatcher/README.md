# webhookcatcher

A small HTTP server that receives incoming webhook requests, verifies their authenticity, and executes configured actions. Designed to sit behind a reverse proxy (Caddy) that forwards external webhook traffic over a unix socket.

## Usage

```
webhookcatcher <config-path>
```

Takes exactly one argument: the absolute path to a TOML configuration file. Any other invocation prints a usage message and exits with code 1.

## How it works

1. Listens on a unix socket (provided via systemd socket activation)
2. Matches incoming requests by path — each hook is identified by a UUID in the URL path (e.g. `/a1b2c3d4-e5f6-7890-...`)
3. Optionally runs one or more verifiers against the request; all must pass
4. Executes configured actions (forward the request, print it, etc.)

Unmatched paths return 404. Failed verification returns 401.

## Configuration

The listen socket is **not** configured here — it comes from systemd socket
activation (`LISTEN_FDS`, fd 3). The config file describes only hooks.

```toml
[[hook]]
id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

  [[hook.verify]]
  type = "hmac"
  header = "X-Hub-Signature-256"
  secret_file = "/run/credentials/my-webhook.secret"

  [hook.actions.forward]
  url = "http://localhost:9000/deploy"

  [hook.actions.print]
```

### `[[hook]]`

| Field | Required | Description                          |
|-------|----------|--------------------------------------|
| `id`  | yes      | UUID used as the URL path for this hook |

### `[[hook.verify]]`

Optional, repeatable. Each entry is a verifier; **all** declared verifiers
must pass or the request is rejected with 401. Omit entirely to accept any
request matching the hook id.

| Field         | Required | Description                                    |
|---------------|----------|------------------------------------------------|
| `type`        | yes      | Verifier kind: `hmac` or `header-secret`       |
| `header`      | yes      | Name of the HTTP header to read                |
| `secret_file` | yes      | Path to a file containing the secret           |

Verifier types:

- **`hmac`** — recomputes `HMAC-SHA256(rawBody, secret)` and compares (constant
  time) against the header value, which must be formatted as `sha256=<hex>`
  (GitHub's `X-Hub-Signature-256` scheme).
- **`header-secret`** — compares the header value for exact equality with the
  secret (constant time). Used by forges that send a static shared token
  (e.g. GitLab's `X-Gitlab-Token`).

Secrets are read from files (not stored in the config) so they can be provided
via systemd credentials or similar mechanisms. Trailing whitespace is trimmed.

### `[hook.actions]`

At least one action is required per hook. Multiple actions can be configured and all will execute.

#### `[hook.actions.forward]`

Proxies the full incoming request (method, headers, body) to the configured URL and returns the upstream response.

| Field | Required | Description          |
|-------|----------|----------------------|
| `url` | yes      | Destination URL      |

#### `[hook.actions.print]`

Logs the request method, path, headers, and body to stdout. No configuration fields — presence enables it.

## Caddy integration

Configure Caddy to forward webhook traffic to the unix socket:

```
webhooks.example.com {
    reverse_proxy unix//run/webhookcatcher/webhookcatcher.sock
}
```
