{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types mkIf;

  # Recursive keybinding node type
  keybindingNodeType = types.submodule {
    options = {
      desc = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Description for WhichKey group";
      };

      defaults = mkOption {
        type = types.submodule {
          options = {
            mode = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
            };
            silent = mkOption {
              type = types.nullOr types.bool;
              default = null;
            };
            lua = mkOption {
              type = types.nullOr types.bool;
              default = null;
            };
          };
        };
        default = {};
        description = "Defaults for direct keys in this group";
      };

      keys = mkOption {
        type = types.attrsOf (types.addCheck (types.submodule {
            options = {
              desc = mkOption {
                type = types.str;
                description = "Key description";
              };

              # Mutually exclusive action types - specify exactly one
              cmd = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Vim command string. Use for commands like "<cmd>edit #<cr>".
                  Mutually exclusive with lua, luaFn, and raw.
                '';
              };

              lua = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Lua function call (auto-wrapped in function() ... end).
                  Use for simple function calls like "snacks.picker.smart()".
                  Mutually exclusive with cmd, luaFn, and raw.

                  Example: lua = "vim.lsp.buf.hover()";
                '';
              };

              luaFn = mkOption {
                type = types.nullOr types.anything;
                default = null;
                description = ''
                  Inline Lua function using lib.mkLuaInline.
                  Use for complex logic that needs multiple statements.
                  Mutually exclusive with cmd, lua, and raw.

                  Example: luaFn = lib.mkLuaInline "function() ... end";
                '';
              };

              raw = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Raw action string (passed through unchanged).
                  Use when you need direct control over the action format.
                  Mutually exclusive with cmd, lua, and luaFn.
                '';
              };

              mode = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "Modes (overrides group default)";
              };

              silent = mkOption {
                type = types.nullOr types.bool;
                default = null;
              };
            };
          }) (binding: let
            actionTypes = [binding.cmd binding.lua binding.luaFn binding.raw];
            nonNullCount = lib.length (lib.filter (x: x != null) actionTypes);
          in
            if nonNullCount == 1
            then true
            else throw "Keybinding must specify exactly one action type (cmd, lua, luaFn, or raw). Currently specified: ${toString nonNullCount}"));
        default = {};
        description = "Direct keybindings at this level";
      };

      groups = mkOption {
        type = types.attrsOf keybindingNodeType;
        default = {};
        description = "Nested subgroups";
      };
    };
  };

  # Helper functions

  processAction = binding:
    if binding.cmd != null
    then binding.cmd
    else if binding.lua != null
    then "function() ${binding.lua} end"
    else if binding.luaFn != null
    then
      if builtins.isAttrs binding.luaFn && binding.luaFn ? expr
      then binding.luaFn.expr # Extract from lib.mkLuaInline
      else binding.luaFn # Use as-is if already a string
    else binding.raw; # Assertions guarantee exactly one action type is set

  flattenKeybindings = prefix: node: let
    nodeDefaults = node.defaults or {};
    directKeys =
      lib.mapAttrsToList (key: binding: {
        key = "${prefix}${key}";
        inherit (binding) desc;
        mode =
          if binding.mode != null
          then binding.mode
          else if nodeDefaults.mode != null
          then nodeDefaults.mode
          else ["n"];
        silent =
          if binding.silent != null
          then binding.silent
          else if nodeDefaults.silent != null
          then nodeDefaults.silent
          else true;
        lua =
          # Determine if this is a Lua action based on action type
          if binding.lua != null || binding.luaFn != null
          then true
          else false;
        action = processAction binding;
      })
      node.keys or {};
    groupKeys = lib.flatten (lib.mapAttrsToList (
        groupKey: groupNode:
          flattenKeybindings "${prefix}${groupKey}" groupNode
      )
      node.groups or {});
  in
    directKeys ++ groupKeys;

  extractWhichKeyGroups = prefix: node: let
    currentGroups =
      lib.mapAttrsToList (
        groupKey: groupNode: let
          fullPrefix = "${prefix}${groupKey}";
        in
          lib.optionalAttrs (groupNode.desc != null) {
            "${fullPrefix}" = groupNode.desc;
          }
      )
      node.groups or {};
    subGroups = lib.flatten (lib.mapAttrsToList (
        groupKey: groupNode:
          extractWhichKeyGroups "${prefix}${groupKey}" groupNode
      )
      node.groups or {});
  in
    lib.mergeAttrsList (currentGroups ++ subGroups);
in {
  options.vim.keybindingTree = mkOption {
    type = keybindingNodeType;
    default = {
      keys = {};
      groups = {};
    };
    description = "Tree-structured keybinding configuration";
  };

  config = mkIf (config.vim.keybindingTree
    != {
      keys = {};
      groups = {};
    }) {
    vim.keymaps = flattenKeybindings "" config.vim.keybindingTree;
    vim.binds.whichKey = {
      enable = true;
      register = extractWhichKeyGroups "" config.vim.keybindingTree;
    };
  };
}
