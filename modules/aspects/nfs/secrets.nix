{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) enabledHosts peersFor wgPrivName wgPubName;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  hosts = builtins.attrNames (enabledHosts denHosts);

  # wireguard-tools on PATH for the inline generators.
  wgPath = pkgs: [pkgs.wireguard-tools];

  # For host H: its private key (used by H's own wg-nfs unit) and its public key
  # (derived from the private key, distributed to every peer's wg-nfs unit).
  secretsFor = h: {
    ${wgPrivName h} = {
      origin = h;
      generator = {
        script = "wg genkey";
        path = wgPath;
      };
      use.${h}.services.wg-nfs = {
        credential.name = "wg-priv";
        restartOnChange = true;
      };
    };
    ${wgPubName h} = {
      origin = h;
      generator = {
        # `needs` delivers the private key as a credential file; wg pubkey reads
        # it from stdin, so feed the file in (it does not auto-pipe).
        script = ''wg pubkey < "$CREDENTIALS_DIRECTORY/${wgPrivName h}"'';
        path = wgPath;
        needs = [(wgPrivName h)];
        # `needs` only orders after the priv *target* (reached before the key is
        # generated at boot); also wait for the priv *provision* to finish so the
        # credential blob actually exists when wg pubkey reads it.
        after = ["secret-provision-${wgPrivName h}.service"];
      };
      use = lib.genAttrs (peersFor h denHosts) (_peer: {
        services.wg-nfs = {
          credential.name = wgPubName h;
          restartOnChange = true;
        };
      });
    };
  };
in {
  config.fleet.secrets = lib.mkMerge (map secretsFor hosts);
}
