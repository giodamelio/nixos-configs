{lib}: rec {
  isStatic = host: (host.network.mode or "unmanaged") == "static";

  # Hosts with statically-addressed interfaces (the only ones readers derive from).
  staticHosts = denHosts: lib.filterAttrs (_name: isStatic) denHosts;

  # All static interface names / addresses on a host ([] when not static). Readers
  # that legitimately handle many (e.g. samba binding several NICs) use these.
  interfacesOf = host:
    if isStatic host
    then lib.attrNames host.network.interfaces
    else [];
  addressesOf = host:
    if isStatic host
    then lib.mapAttrsToList (_n: i: i.address) host.network.interfaces
    else [];

  # Static ULA (IPv6) addresses on a host, with the /prefix stripped — for AAAA
  # records. Interfaces without a `ula` contribute nothing ([] when not static).
  ulasOf = host:
    if isStatic host
    then
      lib.pipe host.network.interfaces [
        lib.attrValues
        (lib.filter (i: i.ula != null))
        (map (i: lib.head (lib.splitString "/" i.ula)))
      ]
    else [];

  # Exactly-one accessors for readers that can only consume a single value
  # (consul bind, nfs endpoint). The throw on >1 is deliberate: it's the signal to
  # introduce interface roles the day a host grows a second, purpose-distinct NIC.
  theInterface = host: let
    names = interfacesOf host;
  in
    if !(isStatic host)
    then throw "network: host uses ${host.network.mode or "unmanaged"} networking; no static interface to select"
    else if names == []
    then throw "network: static host has no interfaces"
    else if lib.length names == 1
    then lib.head names
    else throw "network: host has ${toString (lib.length names)} static interfaces; cannot pick one (add interface roles)";
  theAddress = host: host.network.interfaces.${theInterface host}.address;

  # Fleet-wide: addresses of every static host that serves DNS, for the ns/resolver
  # records. Pre-filtered + total, so callers never face a null/empty per host.
  dnsServerAddresses = denHosts:
    lib.pipe (staticHosts denHosts) [
      (lib.filterAttrs (_n: host: host.dns.serve.enable or false))
      (lib.mapAttrsToList (_n: theAddress))
    ];
}
