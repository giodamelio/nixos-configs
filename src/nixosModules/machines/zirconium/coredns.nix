{homelab, ...}: {pkgs, ...}: let
  membersList =
    pkgs.lib.mapAttrsToList
    (host: ip: "${ip}\t${host}.n.gio.ninja")
    homelab.networks.nebula-homelab.members;
  hostsFile = pkgs.writeTextFile {
    name = "coredns-nebula-hosts";
    text = pkgs.lib.concatStringsSep "\n" membersList;
  };
in {
  services.coredns = {
    enable = true;
    config = ''
      n.gio.ninja {
        hosts ${hostsFile} {
          fallthrough
        }
        forward . 8.8.8.8
      }

      . {
        forward . 8.8.8.8
      }
    '';
  };
}
