data "toml_file" "homelab" {
  input = file("../homelab.toml")
}

resource "cloudflare_record" "machine" {
  for_each = jsondecode(data.toml_file.homelab.content_json).networks.homelab-mesh.members

  name    = each.key
  proxied = false
  ttl     = 1
  type    = "A"
  value   = each.value
  zone_id = data.cloudflare_zone.gio-ninja.zone_id
}
