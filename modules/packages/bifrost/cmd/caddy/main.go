package main

import (
	caddycmd "github.com/caddyserver/caddy/v2/cmd"

	// modules/standard minus caddypki/acmeserver: its badger dependency can't
	// build against the ristretto version fosite needs, and bifrost never
	// runs an ACME server.
	_ "github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	_ "github.com/caddyserver/caddy/v2/modules/caddyevents"
	_ "github.com/caddyserver/caddy/v2/modules/caddyevents/eventsconfig"
	_ "github.com/caddyserver/caddy/v2/modules/caddyfs"
	_ "github.com/caddyserver/caddy/v2/modules/caddyhttp/standard"
	_ "github.com/caddyserver/caddy/v2/modules/caddypki"
	_ "github.com/caddyserver/caddy/v2/modules/caddytls"
	_ "github.com/caddyserver/caddy/v2/modules/caddytls/distributedstek"
	_ "github.com/caddyserver/caddy/v2/modules/caddytls/standardstek"
	_ "github.com/caddyserver/caddy/v2/modules/filestorage"
	_ "github.com/caddyserver/caddy/v2/modules/logging"
	_ "github.com/caddyserver/caddy/v2/modules/metrics"

	_ "github.com/caddy-dns/cloudflare"
	_ "github.com/mholt/caddy-dynamicdns"
	_ "github.com/mholt/caddy-ratelimit"

	_ "gio.ninja/bifrost"
)

func main() {
	caddycmd.Main()
}
