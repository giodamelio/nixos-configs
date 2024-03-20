data "toml_file" "homelab" {
  input = file("../homelab.toml")
}

locals {
  homelab_mesh = jsondecode(data.toml_file.homelab.content_json).networks.homelab-mesh
}

resource "cloudflare_record" "machine" {
  for_each = local.homelab_mesh.members

  name    = each.key
  proxied = false
  ttl     = 1
  type    = "A"
  value   = each.value
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}

resource "cloudflare_record" "alias" {
  for_each = local.homelab_mesh.aliases

  name    = each.key
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = each.value
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}
