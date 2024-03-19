resource "cloudflare_record" "defguard" {
  name    = "defguard"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "zirconium.gio.ninja"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "defguard-enroll" {
  name    = "enroll.defguard"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "zirconium.gio.ninja"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}
