# Per-host expansion of the fleet.secrets registry into systemd units. Pure:
# everything it needs arrives as arguments, so both the den aspect
# (fleet-secrets.nix) and the VM test (_test.nix) call it directly. Returns a
# NixOS module for one host.
{lib}: {
  registry, # validated, enabled fleet.secrets entries
  hostName, # the host this module is for
  credsync, # the credsync package
  pushKeys, # homelab.toml [credsync_push_keys]
  pushUser ? "server", # non-root SSH user (passwordless sudo) that receives pushes
  enablePushes ? true, # emit the push oneshots + hourly retry timers
}: {
  config,
  pkgs,
  ...
}: let
  l = import ./_lib.nix {inherit lib;};
  inherit
    (l)
    credentialId
    sitePath
    credentialDirective
    enabledSitesOn
    copySet
    holdsSecret
    generatorActive
    ;

  domain = "gio.ninja";
  credstoreDir = "/usr/lib/credstore.encrypted";
  pushKeyName = "credsync-push-key";

  credsyncExe = lib.getExe credsync;

  originSecrets = lib.filterAttrs (_n: s: s.origin == hostName) registry;
  heldSecrets = lib.filterAttrs (_n: s: holdsSecret s hostName) registry;

  blobPath = name: "${credstoreDir}/${name}";

  # --- push identity (dedicated per-host key, not root's ~/.ssh) ---
  # Origins that push some secret held here TO this host (who to authorize).
  pushOriginsHere = lib.pipe heldSecrets [
    (lib.filterAttrs (_n: s: s.origin != hostName && builtins.elem hostName (copySet s)))
    (lib.mapAttrsToList (_n: s: s.origin))
    lib.unique
  ];
  # This host pushes iff it originates a secret with a non-empty copy set.
  hostPushes = lib.any (s: copySet s != []) (lib.attrValues originSecrets);

  pushKeygenExe = lib.getExe (pkgs.writeShellApplication {
    name = "credsync-push-keygen";
    runtimeInputs = [pkgs.openssh pkgs.systemd pkgs.coreutils];
    text = ''
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT
      ssh-keygen -t ed25519 -N "" -C "credsync-push@${hostName}" -f "$tmp/key" >/dev/null
      install -d -m 0700 ${credstoreDir}
      systemd-creds encrypt --name=${pushKeyName} "$tmp/key" ${blobPath pushKeyName}
      chmod 600 ${blobPath pushKeyName}
      install -m 0644 "$tmp/key.pub" /etc/${pushKeyName}.pub
      echo "credsync push public key for ${hostName}:"
      cat /etc/${pushKeyName}.pub
      echo "Add it to homelab.toml under [credsync_push_keys].${hostName}"
    '';
  });

  # Forced-command wrapper: a push key may only ever run `credsync write`.
  forcedCommandExe = lib.getExe (pkgs.writeShellApplication {
    name = "credsync-forced-command";
    runtimeInputs = [credsync];
    text = ''
      cmd="''${SSH_ORIGINAL_COMMAND:-}"
      case "$cmd" in
        "credsync write "*) ;;
        *)
          echo "credsync: only 'credsync write' is permitted via this key" >&2
          exit 1
          ;;
      esac
      # shellcheck disable=SC2086 # deliberate: re-run the validated command
      exec $cmd
    '';
  });

  # --- generator -> executable producing the secret on stdout ---
  genExe = name: g:
    if lib.isDerivation g.script
    then lib.getExe g.script
    else if builtins.isPath g.script
    then "${pkgs.runCommandLocal "secret-gen-${name}" {} ''
      install -Dm755 ${g.script} $out/bin/gen
    ''}/bin/gen"
    else
      lib.getExe (pkgs.writeShellApplication {
        name = "secret-gen-${name}";
        # User PATH first (can shadow), then a base of common token tooling so
        # the spec's `generator = "openssl rand -hex 32"` shorthand just works.
        runtimeInputs = g.path pkgs ++ [pkgs.coreutils pkgs.openssl];
        text = g.script;
      });

  provisionExe = name: s:
    lib.getExe (pkgs.writeShellApplication {
      name = "secret-provision-${name}";
      runtimeInputs = [credsync];
      text =
        if generatorActive s
        then "${genExe name s.generator} | credsync write ${name}"
        else ''
          echo "secret '${name}' not provisioned on ${hostName}." >&2
          echo "run: <value> | credsync write ${name}" >&2
          exit 1
        '';
    });

  # --- per-site credential drop-in (load + target gating; both types) ---
  siteDropin = secretName: site: let
    id = credentialId secretName site;
  in
    pkgs.runCommandLocal "secret-dropin-${secretName}-${site.unit}-${id}" {} ''
      d="$out/etc/systemd/system/${site.unit}.service.d"
      mkdir -p "$d"
      cat > "$d/50-secret-${secretName}-${id}.conf" <<'EOF'
      [Unit]
      Requires=secret-${secretName}.target
      After=secret-${secretName}.target

      [Service]
      ${credentialDirective secretName site}
      EOF
    '';

  # --- env-wrapper: group env-wrapper sites on this host by target unit ---
  # [{ secretName, site }] for every enabled env-wrapper site held here.
  envWrapperSites = lib.flatten (lib.mapAttrsToList (
      secretName: s:
        map (e: {inherit secretName;} // e)
        (builtins.filter (e: e.site.type == "env-wrapper") (enabledSitesOn s hostName))
    )
    heldSecrets);
  envWrapperByUnit = builtins.groupBy (e: e.site.unit) envWrapperSites;

  envWrapperDropin = unit: entries: let
    origExecStart = config.systemd.services.${unit}.serviceConfig.ExecStart or null;
    exports = lib.pipe entries [
      (map (e: {
        var = e.site.env-wrapper.variable;
        cred = credentialId e.secretName e.site;
      }))
      (lib.sort (a: b: a.var < b.var))
    ];
    vars = map (x: x.var) exports;
    dupVars = lib.pipe vars [
      (builtins.groupBy lib.id)
      (lib.filterAttrs (_k: v: builtins.length v > 1))
      builtins.attrNames
    ];
    _checked =
      # A single ExecStart (string, path, or derivation) is fine — it coerces to
      # a command below. Only none or list-form (multiple ExecStart) is an error.
      if origExecStart == null || builtins.isList origExecStart
      then throw "fleet.secrets: env-wrapper on '${unit}' needs exactly one ExecStart (found none or a list)"
      else if dupVars != []
      then throw "fleet.secrets: env-wrapper on '${unit}' exports duplicate variables: ${lib.concatStringsSep ", " dupVars}"
      else true;
    wrapper = pkgs.writeShellScript "${unit}-secret-env-wrapper" ''
      ${lib.concatMapStringsSep "\n" (x: ''export ${x.var}="$(cat "$CREDENTIALS_DIRECTORY/${x.cred}")"'') exports}
      exec ${origExecStart}
    '';
  in
    assert _checked;
      pkgs.runCommandLocal "secret-envwrap-${unit}" {} ''
        d="$out/etc/systemd/system/${unit}.service.d"
        mkdir -p "$d"
        cat > "$d/60-secret-env-wrapper.conf" <<EOF
        [Service]
        ExecStart=
        ExecStart=${wrapper}
        EOF
      '';

  # --- collect all drop-in packages for this host ---
  siteDropins = lib.flatten (lib.mapAttrsToList (
      secretName: s: map (e: siteDropin secretName e.site) (enabledSitesOn s hostName)
    )
    heldSecrets);
  envWrapperDropins = lib.mapAttrsToList envWrapperDropin envWrapperByUnit;

  # Units consuming a secret on this host, split by uphold preference.
  consumerUnits = secret: predicate:
    lib.unique (map (e: "${e.site.unit}.service")
      (builtins.filter (e: predicate e.site) (enabledSitesOn secret hostName)));

  # Units this host should warn about if absent from systemd.services.
  referencedUnits = lib.unique (lib.flatten (lib.mapAttrsToList (
      _n: s: map (e: e.site.unit) (enabledSitesOn s hostName)
    )
    heldSecrets));
  missingUnits = builtins.filter (u: !(config.systemd.services ? ${u})) referencedUnits;

  # --- login warning for missing secrets ---
  statusMessage = e:
    if e.here && e.manual
    then "secret '${e.name}' not provisioned — run: <value> | credsync write ${e.name}"
    else if e.here
    then "secret '${e.name}' not yet generated"
    else "waiting for '${e.name}' from ${e.origin}";
  statusEntries =
    lib.mapAttrsToList (name: s: {
      inherit name;
      inherit (s) origin;
      manual = !(generatorActive s);
      here = s.origin == hostName;
    })
    heldSecrets;
  statusExe = lib.getExe (pkgs.writeShellApplication {
    name = "fleet-secrets-status";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      issue=/run/issue.d/fleet-secrets.issue
      warnings=""
      # Messages are static and built from validated [a-z0-9-] names, so they
      # embed safely inside the double-quoted append below.
      add() { warnings="''${warnings}$1"$'\n'; }
      ${lib.concatMapStringsSep "\n" (e: ''
          if [ ! -e ${blobPath e.name} ]; then add "${statusMessage e}"; fi
        '')
        statusEntries}
      install -d -m 0755 /run/issue.d
      if [ -n "$warnings" ]; then
        {
          echo "fleet.secrets — missing on ${hostName}:"
          printf '%s' "$warnings"
        } > "$issue"
      else
        rm -f "$issue"
      fi
    '';
  });
in {
  options.fleet.secrets = lib.mkOption {
    readOnly = true;
    default = {};
    description = "Read-only per-host view of fleet.secrets: .path / .paths.<site>.";
    type = lib.types.lazyAttrsOf (lib.types.submodule {
      options = {
        # raw keeps `path`'s ambiguity-throw lazy (str.check would force it).
        path = lib.mkOption {type = lib.types.raw;};
        paths = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
      };
    });
  };

  config = lib.mkMerge [
    # Read-only mirror for secrets held on this host.
    {
      fleet.secrets =
        lib.mapAttrs (secretName: s: let
          sites = enabledSitesOn s hostName;
          paths = lib.listToAttrs (map (e: lib.nameValuePair e.siteName (sitePath secretName e.site)) sites);
        in {
          inherit paths;
          path =
            if builtins.length sites == 1
            then sitePath secretName (builtins.head sites).site
            else
              throw (
                if sites == []
                then "fleet.secrets.${secretName}.path: no use-site on ${hostName}"
                else "fleet.secrets.${secretName}.path: ${toString (builtins.length sites)} sites on ${hostName}; use .paths.<site>"
              );
        })
        heldSecrets;
    }

    (lib.mkIf (missingUnits != []) {
      warnings =
        map (u: "fleet.secrets: unit '${u}.service' is referenced by a use-site on ${hostName} but is not defined in systemd.services") missingUnits;
    })

    # --- Origin: provision + push ---
    {
      systemd.services = lib.mkMerge (
        # provision oneshots
        (lib.mapAttrsToList (name: s: {
            "secret-provision-${name}" = {
              description = "Provision secret ${name}";
              wantedBy = ["multi-user.target"];
              after =
                ["network.target"]
                ++ lib.optionals (s.generator != null) s.generator.after
                ++ lib.optionals (s.generator != null) (map (need: "secret-${need}.target") s.generator.needs);
              requires =
                lib.optionals (s.generator != null) (map (need: "secret-${need}.target") s.generator.needs);
              unitConfig.ConditionPathExists = "!${blobPath name}";
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = false;
                LoadCredentialEncrypted = lib.optionals (s.generator != null) s.generator.needs;
                ExecStart = provisionExe name s;
              };
            };
          })
          originSecrets)
        # push oneshots per destination
        ++ lib.optionals enablePushes (lib.flatten (lib.mapAttrsToList (
            name: s:
              map (dest: let
                restartUnits =
                  lib.unique (map (e: "${e.site.unit}.service")
                    (builtins.filter (e: e.site.restartOnChange) (enabledSitesOn s dest)));
              in {
                "secret-push-${name}@${dest}" = {
                  description = "Push secret ${name} to ${dest}";
                  after = ["network-online.target" "secret-provision-${name}.service" "credsync-push-keygen.service"];
                  wants = ["network-online.target" "credsync-push-keygen.service"];
                  requires = ["secret-provision-${name}.service"];
                  serviceConfig = {
                    Type = "oneshot";
                    LoadCredentialEncrypted = [pushKeyName];
                    Environment = ["CREDSYNC_SSH_IDENTITY=%d/${pushKeyName}"];
                    ExecStart = "${credsyncExe} push ${name} root@${dest}.${domain} ${lib.concatStringsSep " " restartUnits}";
                  };
                };
              }) (copySet s)
          )
          originSecrets))
      );

      systemd.timers = lib.mkIf enablePushes (lib.mkMerge (lib.flatten (lib.mapAttrsToList (
          name: s:
            map (dest: {
              "secret-push-${name}@${dest}" = {
                description = "Periodic push of secret ${name} to ${dest}";
                wantedBy = ["timers.target"];
                timerConfig = {
                  OnBootSec = "1min";
                  OnUnitActiveSec = "1h";
                  Unit = "secret-push-${name}@${dest}.service";
                };
              };
            }) (copySet s)
        )
        originSecrets)));
    }

    # --- Holders: path + target watching the blob ---
    {
      systemd.paths = lib.mapAttrs' (name: _s:
        lib.nameValuePair "secret-${name}" {
          description = "Watch for secret ${name}";
          wantedBy = ["multi-user.target"];
          pathConfig = {
            PathExists = blobPath name;
            Unit = "secret-${name}.target";
          };
        })
      heldSecrets;

      systemd.targets = lib.mapAttrs' (name: s: let
        wantsUnits = consumerUnits s (site: !site.upholds);
        upholdsUnits = consumerUnits s (site: site.upholds);
      in
        lib.nameValuePair "secret-${name}" {
          description = "Secret ${name} present";
          # Re-run the login warning whenever a secret lands, so it self-clears.
          wants = wantsUnits ++ ["fleet-secrets-status.service"];
          unitConfig = lib.mkIf (upholdsUnits != []) {Upholds = upholdsUnits;};
        })
      heldSecrets;
    }

    # --- Consumer drop-ins (per-site credential load + per-unit env wrapper) ---
    {
      systemd.packages = siteDropins ++ envWrapperDropins;
    }

    # --- Push identity: first-boot keygen + receiver authorization ---
    (lib.mkIf hostPushes {
      systemd.services.credsync-push-keygen = {
        description = "Generate the credsync push identity for ${hostName}";
        wantedBy = ["multi-user.target"];
        unitConfig.ConditionPathExists = "!${blobPath pushKeyName}";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          ExecStart = pushKeygenExe;
        };
      };
    })

    {
      # Each origin pushing to this host gets a forced-command key locked to
      # `credsync write`. Origins whose pubkey isn't in homelab.toml yet are
      # skipped (their push fails until the key is pasted — surfaced at login).
      users.users.root.openssh.authorizedKeys.keys =
        map (origin: ''command="${forcedCommandExe}",restrict ${pushKeys.${origin}}'')
        (builtins.filter (origin: pushKeys ? ${origin}) pushOriginsHere);
    }

    # --- Login warning for missing/in-transit secrets ---
    (lib.mkIf (heldSecrets != {}) {
      systemd.services.fleet-secrets-status = {
        description = "Report missing fleet secrets at login";
        wantedBy = ["multi-user.target"];
        after = lib.mapAttrsToList (name: _: "secret-${name}.target") heldSecrets;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          ExecStart = statusExe;
        };
      };

      # agetty reads /run/issue.d natively (console); login shells (incl. ssh)
      # print it here, since NixOS pam_motd only serves a single static file.
      environment.loginShellInit = ''
        if [ -s /run/issue.d/fleet-secrets.issue ]; then
          cat /run/issue.d/fleet-secrets.issue
        fi
      '';
    })
  ];
}
