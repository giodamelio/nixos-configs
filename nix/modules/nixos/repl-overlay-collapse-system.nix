# Repl overlay that makes accessing any object path that has ${system} in it easier
# Original attributes are available below original
info: _final: attrs: let
  # Equivalent to nixpkgs `lib.optionalAttrs`.
  optionalAttrs = predicate: attrs:
    if predicate
    then attrs
    else {};

  # If `attrs.${oldName}.${info.currentSystem}` exists, alias `${newName}` to it.
  collapseRenamed = oldName: newName:
    optionalAttrs ((builtins.hasAttr oldName attrs)
      && (builtins.isAttrs attrs.${oldName})
      && (builtins.hasAttr info.currentSystem attrs.${oldName}))
    {
      ${newName} = attrs.${oldName}.${info.currentSystem};
    };

  # Alias `attrs.${oldName}.${info.currentSystem} to `${newName}`.
  collapse = name: collapseRenamed name name;

  # Alias all `attrs` keys with an `${info.currentSystem}` attribute.
  collapseAll =
    builtins.foldl'
    (prev: name: prev // (collapse name))
    {}
    (builtins.attrNames attrs);
in
  # Preserve the original bindings as `original`.
  (optionalAttrs (! attrs ? original)
    {
      original = attrs;
    })
  // collapseAll
