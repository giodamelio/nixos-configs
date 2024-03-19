resource "cloudflare_record" "fastmail-dkim-1" {
  name    = "fm1._domainkey"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "fm1.gio.ninja.dkim.fmhosted.com"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-dkim-2" {
  name    = "fm2._domainkey"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "fm2.gio.ninja.dkim.fmhosted.com"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-dkim-3" {
  name    = "fm3._domainkey"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "fm3.gio.ninja.dkim.fmhosted.com"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-smtp-wildcard-2" {
  name     = "*"
  priority = 20
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "in2-smtp.messagingengine.com"
  zone_id  = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-smtp-wildcard-1" {
  name     = "*"
  priority = 10
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "in1-smtp.messagingengine.com"
  zone_id  = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-smtp-root-2" {
  name     = "gio.ninja"
  priority = 20
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "in2-smtp.messagingengine.com"
  zone_id  = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-smtp-root-1" {
  name     = "gio.ninja"
  priority = 10
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "in1-smtp.messagingengine.com"
  zone_id  = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-smtp-www-2" {
  name     = "www"
  priority = 20
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "in2-smtp.messagingengine.com"
  zone_id  = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-smtp-www-1" {
  name     = "www"
  priority = 10
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "in1-smtp.messagingengine.com"
  zone_id  = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-dmarc" {
  name    = "_dmarc"
  proxied = false
  ttl     = 1
  type    = "TXT"
  value   = "v=DMARC1;  p=none; rua=mailto:890a41424dbf4571a5833b5edd6e7260@dmarc-reports.cloudflare.net"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "fastmail-spf" {
  name    = "gio.ninja"
  proxied = false
  ttl     = 1
  type    = "TXT"
  value   = "v=spf1 include:spf.messagingengine.com ?all"
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}
