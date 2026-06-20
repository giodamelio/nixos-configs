{lib}: let
  net = import ../network/_lib.nix {inherit lib;};
in rec {
  # Static hosts -> { <host>.A = [addr...]; (AAAA = [ula...];) } subzone fragment,
  # so <host>.<zone> resolves directly. Addresses come from host.network (dynamic
  # hosts get none); AAAA only when the host has a static ULA.
  hostARecords = denHosts:
    lib.mapAttrs (_name: host:
      {A = net.addressesOf host;}
      // lib.optionalAttrs (net.ulasOf host != []) {AAAA = net.ulasOf host;})
    (net.staticHosts denHosts);
}
