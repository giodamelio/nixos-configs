# The fleet.secrets den aspect: validates the registry (against the den host
# list, at flake-parts scope) and hands the validated, enabled set to the pure
# per-host expansion in _expand.nix. Keeping emission in _expand.nix lets the
# VM test (_test.nix) build the same units for plain test nodes.
{
  lib,
  config,
  ...
}: let
  l = import ./_lib.nix {inherit lib;};
  inherit
    (l)
    validName
    validCredentialId
    flattenHosts
    credentialId
    enabledSitesOn
    enabledSecrets
    generatorActive
    ;

  # Per-host credsync push public keys, pasted from each host's first-boot
  # credsync-push-keygen output (same print-and-paste loop as the wg mesh keys).
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
  pushKeys = homelab.credsync_push_keys or {};

  # Full registry (incl. disabled) for needs lookups; enabled set for emission.
  allSecrets = config.fleet.secrets;
  secrets = enabledSecrets allSecrets;
  denHosts = flattenHosts config.den.hosts;
  hostExists = name: denHosts ? ${name};

  # needs that actually exist (the unknown-need check reports the rest nicely).
  needsOf = name: let
    g = (allSecrets.${name} or {generator = null;}).generator;
  in
    if g == null
    then []
    else builtins.filter (m: allSecrets ? ${m}) g.needs;

  # A secret reaches itself iff its needs graph contains a cycle through it.
  reachable = start: let
    step = acc: let
      merged = lib.unique (acc ++ lib.flatten (map needsOf acc));
    in
      if merged == acc
      then acc
      else step merged;
  in
    step (needsOf start);

  # Per-secret eval-time checks (eager throws, ssh-access convention). Returns
  # the secret unchanged so the result can be referenced to force the checks.
  checkSecret = secretName: secret: let
    fail = msg: throw "fleet.secrets.${secretName}: ${msg}";
    g = secret.generator;
    sites = lib.flatten (lib.mapAttrsToList (host: _: map (e: {inherit host;} // e) (enabledSitesOn secret host)) secret.use);
    # credential ids must be unique per (host, unit).
    idKey = e: "${e.host}\t${e.site.unit}\t${credentialId secretName e.site}";
    dupKeys = lib.pipe sites [
      (map idKey)
      (builtins.groupBy lib.id)
      (lib.filterAttrs (_k: v: builtins.length v > 1))
      builtins.attrNames
    ];
    checks =
      [
        {
          ok = validName secretName;
          msg = "secret name must match [a-z0-9-]+";
        }
        {
          ok = hostExists secret.origin;
          msg = "origin '${secret.origin}' is not a den host";
        }
        {
          ok = !(builtins.elem secret.origin secret.copyTo);
          msg = "origin '${secret.origin}' must not appear in copyTo";
        }
        {
          ok = !(generatorActive secret) || g.script != null;
          msg = "generator.enable = true but no generator.script";
        }
        {
          ok = !(builtins.elem secretName (reachable secretName));
          msg = "generator.needs graph is cyclic";
        }
        {
          ok = dupKeys == [];
          msg = "duplicate credential id for one (host, unit): ${lib.concatStringsSep ", " dupKeys}";
        }
      ]
      ++ lib.mapAttrsToList (host: _: {
        ok = hostExists host;
        msg = "use host '${host}' is not a den host";
      })
      secret.use
      ++ map (h: {
        ok = hostExists h;
        msg = "copyTo host '${h}' is not a den host";
      })
      secret.copyTo
      ++ lib.optionals (g != null) (map (need: {
          ok = allSecrets ? ${need};
          msg = "generator.needs references unknown secret '${need}'";
        })
        g.needs)
      ++ lib.optionals (g != null) (map (need: {
          ok = !(allSecrets ? ${need}) || allSecrets.${need}.origin == secret.origin;
          msg = "generator.needs '${need}' must share origin '${secret.origin}'";
        })
        g.needs)
      ++ map (e: {
        ok = validCredentialId (credentialId secretName e.site);
        msg = "credential id '${credentialId secretName e.site}' must match [a-z0-9.-]+";
      })
      sites
      ++ map (e: {
        ok = e.site.credential.encrypted || e.site.credential.source != null;
        msg = "${e.site.unit}: credential.encrypted = false requires credential.source";
      })
      sites;
    failures = builtins.filter (c: !c.ok) checks;
  in
    if failures == []
    then secret
    else fail (builtins.head failures).msg;

  # Validated, enabled registry. Referencing this forces every secret's checks.
  checkedSecrets = lib.mapAttrs checkSecret secrets;

  expand = import ./_expand.nix {inherit lib;};
in {
  # The aspect's nixos value is one module-function; den supplies host/perSystem/
  # config/pkgs as module args. _expand returns a {config, pkgs, ...} module-
  # function, which we apply here so the aspect resolves to a plain module.
  den.aspects.fleet-secrets.nixos = {
    host,
    perSystem,
    config,
    pkgs,
    ...
  }:
    expand {
      registry = checkedSecrets;
      hostName = host.name;
      credsync = perSystem.self.credsync;
      inherit pushKeys;
    } {inherit config pkgs;};
}
