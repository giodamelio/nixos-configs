{lib}: rec {
  # Secret names and credential ids end up in literal systemd unit names and
  # credential ids, so keep them to a tame, never-escaped charset.
  nameRe = "[a-z0-9-]+";
  validName = name: builtins.match nameRe name != null;

  # "forgejo-runner-token" -> "FORGEJO_RUNNER_TOKEN". Names are validated to
  # [a-z0-9-]+, so only "-" needs collapsing. The env-wrapper variable default.
  screamingSnake = name: lib.toUpper (builtins.replaceStrings ["-"] ["_"] name);

  # Flatten den.hosts (keyed by system then host) into a single name -> host map.
  flattenHosts = denHosts: lib.concatMapAttrs (_system: hosts: hosts) denHosts;

  # Effective credential id for a use-site: the override, else the secret name.
  credentialId = secretName: site:
    if site.credential.name != null
    then site.credential.name
    else secretName;

  # Runtime path systemd places a use-site's credential at.
  sitePath = secretName: site: "/run/credentials/${site.unit}.service/${credentialId secretName site}";

  # The LoadCredential[Encrypted]= directive for a use-site (spec emission rule):
  #   defaults                  -> D=<secret>
  #   name overridden, no source-> D=<name>:<secret>
  #   source set                -> D=<name>:<source>
  # where D = LoadCredentialEncrypted when encrypted, else LoadCredential.
  credentialDirective = secretName: site: let
    directive =
      if site.credential.encrypted
      then "LoadCredentialEncrypted"
      else "LoadCredential";
    id = credentialId secretName site;
    renamed = site.credential.name != null && site.credential.name != secretName;
    rhs =
      if site.credential.source != null
      then "${id}:${site.credential.source}"
      else if renamed
      then "${id}:${secretName}"
      else secretName;
  in "${directive}=${rhs}";

  # All enabled use-sites of a secret on a given host, as a flat list of
  # { siteName, site } (site is the submodule value). Honors host- and
  # site-level enable.
  enabledSitesOn = secret: hostName: let
    useHost = secret.use.${hostName} or null;
  in
    if useHost == null || !useHost.enable
    then []
    else
      lib.pipe useHost.services [
        (lib.filterAttrs (_siteName: site: site.enable))
        (lib.mapAttrsToList (siteName: site: {inherit siteName site;}))
      ];

  # Hosts that must receive the blob = enabled use-hosts (minus origin) ∪ copyTo.
  copySet = secret:
    lib.unique (
      (lib.pipe secret.use [
        (lib.filterAttrs (_host: useHost: useHost.enable))
        builtins.attrNames
        (builtins.filter (host: host != secret.origin))
      ])
      ++ secret.copyTo
    );

  # Does this host hold the blob at all? (origin always provisions; holders =
  # copy set; origin also holds when it has local uses.)
  holdsSecret = secret: hostName:
    hostName == secret.origin || builtins.elem hostName (copySet secret);

  # Only enabled secrets contribute anything.
  enabledSecrets = secrets: lib.filterAttrs (_name: secret: secret.enable) secrets;
}
