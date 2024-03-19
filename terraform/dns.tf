resource "cloudflare_record" "machine-zirconium-pub" {
  name    = "zirconium.pub"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "5.78.111.5"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "root-cloudflare-pages" {
  name    = "gio.ninja"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  value   = "gio-ninja.pages.dev"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}
