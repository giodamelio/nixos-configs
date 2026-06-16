{lib}: let
  net = import ../network/_lib.nix {inherit lib;};
in rec {
  # Static hosts -> { <host>.A = [addr...]; } subzone fragment, so <host>.<zone>
  # resolves directly. Addresses come from host.network (dynamic hosts get none).
  hostARecords = denHosts:
    lib.mapAttrs (_name: host: {A = net.addressesOf host;}) (net.staticHosts denHosts);
}
