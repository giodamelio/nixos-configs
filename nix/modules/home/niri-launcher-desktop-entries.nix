# Generates XDG desktop entries for gio.niri.binds entries that have a label,
# making them searchable in Noctalia or any XDG-compliant launcher.
#
# Requires niri-launcher-binds.nix to be imported (declares gio.niri.binds).
{
  config,
  lib,
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

  # Build the exec string from an action attrset
  buildExec = action: let
    actionName = builtins.head (builtins.attrNames action);
    actionArgs = action.${actionName};
    argType = builtins.typeOf actionArgs;
  in
    if argType == "set" && actionArgs == {}
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
            exec = buildExec entry.action;
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
}
