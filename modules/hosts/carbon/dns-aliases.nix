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
    unifi.CNAME = ["unifi.lan."];
    jetkvm.CNAME = ["jetkvm.lan."];
    # The router knows the phone by its Android hostname.
    aluminum.CNAME = ["pixel-7.lan."];
    # step-ca on strontium (its own port, not behind Caddy) — CNAME to
    # strontium's auto A record rather than the .lan. forward.
    ca.CNAME = ["strontium.gio.ninja."];
    # Its LAN VPN address: SSH is closed to the internet at OCI. DHCP on a NAT'd
    # VNIC, so it gets no auto A record.
    oganesson.A = ["10.100.0.3"];
  };
}
