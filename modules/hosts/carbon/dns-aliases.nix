# LAN device aliases — bare host names that don't get a den A/AAAA record (the
# dynamic den laptops + external devices) resolve via a CNAME to <name>.lan.,
# which the .lan forward zone hands to the router. The den DNS renderer only emits
# A/AAAA for static den hosts + service endpoints, so these reproduce the Blueprint
# lan-dns cname set for the bare device names. Fleet-wide config, declared here
# since carbon (with gallium) serves the zone. Converted from homelab.toml
# [dns."gio.ninja".cname].
_: {
  fleet.dns.zones."gio.ninja".subdomains = {
    cadmium.CNAME = ["cadmium.lan."];
    cesium.CNAME = ["cesium.lan."];
    rhodium.CNAME = ["rhodium.lan."];
    unifi.CNAME = ["unifi.lan."];
    jetkvm.CNAME = ["jetkvm.lan."];
  };
}
