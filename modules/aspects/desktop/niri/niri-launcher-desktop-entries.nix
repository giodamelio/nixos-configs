# niri-launcher-desktop-entries — generates XDG desktop entries for labeled
# gio.niri.binds, making them searchable in Noctalia / any XDG launcher.
# Converted from nix/modules/home/niri-launcher-desktop-entries.nix.
#
# Requires niri-launcher-binds (declares gio.niri.binds).
_: {
  den.aspects.niri-launcher-desktop-entries.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.gio.niri.binds;
    niri = lib.getExe config.programs.niri.package;

    # Sanitize a keybind string into a valid desktop entry ID
    sanitizeId = key: let
      lowered = lib.toLower key;
      replaced = builtins.replaceStrings ["+"] ["-"] lowered;
      chars = lib.stringToCharacters replaced;
      filtered = builtins.filter (c: builtins.match "[a-z0-9-]" c != null) chars;
    in
      "niri-" + lib.concatStrings filtered;

    # Escape % as %% for .desktop Exec values (% is a field code prefix).
    # Don't add quotes — Home Manager handles quoting when writing the file.
    escapeExecArg = s:
      builtins.replaceStrings ["%"] ["%%"] (toString s);

    # Build the exec string from an action attrset. `id` is the sanitized
    # desktop-entry ID, used to name any generated helper script.
    buildExec = id: action: let
      actionName = builtins.head (builtins.attrNames action);
      actionArgs = action.${actionName};
      argType = builtins.typeOf actionArgs;
    in
      # spawn-sh carries a full shell pipeline (pipes, $(), quotes, % codes)
      # that can't be expressed as a .desktop Exec line. Render it to a script
      # and point Exec at the bare store path — zero quoting hazard.
      if actionName == "spawn-sh"
      then "${pkgs.writeShellScript id actionArgs}"
      else if argType == "set" && actionArgs == {}
      then "${niri} msg action ${actionName}"
      else if argType == "set"
      then builtins.trace "niri-launcher-binds: named attrset args not supported for action ${actionName}, using placeholder" "true"
      else if argType == "list"
      then
        if actionArgs == []
        then "${niri} msg action ${actionName}"
        else "${niri} msg action ${actionName} ${lib.concatMapStringsSep " " escapeExecArg actionArgs}"
      else if argType == "string"
      then "${niri} msg action ${actionName} ${escapeExecArg actionArgs}"
      else if argType == "int" || argType == "float"
      then "${niri} msg action ${actionName} ${toString actionArgs}"
      else "${niri} msg action ${actionName}";

    labeledBinds = lib.filterAttrs (_: entry: entry.label != null) cfg;
  in {
    config = lib.mkIf (labeledBinds != {}) {
      xdg.desktopEntries =
        lib.mapAttrs' (key: entry: {
          name = sanitizeId key;
          value =
            {
              name = "Niri: ${entry.label}";
              exec = buildExec (sanitizeId key) entry.action;
              terminal = false;
              categories = ["Utility"];
              noDisplay = false;
            }
            // lib.optionalAttrs (entry.icon != null) {
              inherit (entry) icon;
            };
        })
        labeledBinds;
    };
  };
}
