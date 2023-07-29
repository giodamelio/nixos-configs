{nixpkgs ? import <nixpkgs> {}}: rec {
  inherit (nixpkgs) lib;
  inherit (lib) strings attrsets lists debug;

  # Helper function to join path components with dashes
  joinPaths = path: strings.concatMapStringsSep "-" (x: toString x) path;

  # Only run the transformer on a subpath of the tree
  subtreeTransformer = subpath: transformer: let
    subpath-length = builtins.length subpath;
  in
    path: children:
      if (lib.take subpath-length path) == subpath
      then transformer path children
      else children;

  # Transform the tree into a single level deep attrset by combining names with dashes
  # e.g. { a = { b = 1; c = 2; } } -> { a-b = 1; a-c = 2 }
  flattenTransformer = path: children:
    mergeAttrsList (flattenOneLevel children);

  # Takes an atterset and turns it into a list of attrsets that have their names flattened one level
  flattenOneLevel = input:
    attrsets.mapAttrsToList
    (name: value:
      if !builtins.isAttrs value
      then {${name} = value;}
      else (attrsets.mapAttrs' (child-name: child-value: attrsets.nameValuePair (name + "-" + child-name) child-value) value))
    input;

  # Used by flatten
  flatten' = input: length: let
    flatter = lists.concatMap flattenOneLevel input;
    new-length = builtins.length flatter;
  in
    if new-length == length
    then mergeAttrsList flatter
    else flatten' flatter new-length;

  # Recursively flattens an attrset by joining all the names by dashes
  flatten = input:
    if !builtins.isAttrs input
    then throw "input must be an attrset"
    else let
      flatter = flattenOneLevel input;
      length = builtins.length flatter;
    in
      flatten' flatter length;

  # Stolen from nixpkgs.lib.attrsets master until it is available here
  # https://github.com/NixOS/nixpkgs/blob/4e90ab6cca0795346b4fbe4ac639ce9cbb72bfb6/lib/attrsets.nix#L741-L775
  mergeAttrsList = list: let
    # `binaryMerge start end` merges the elements at indices `index` of `list` such that `start <= index < end`
    # Type: Int -> Int -> Attrs
    binaryMerge = start: end:
    # assert start < end; # Invariant
      if end - start >= 2
      then
        # If there's at least 2 elements, split the range in two, recurse on each part and merge the result
        # The invariant is satisfied because each half will have at least 1 element
        binaryMerge start (start + (end - start) / 2)
        // binaryMerge (start + (end - start) / 2) end
      else
        # Otherwise there will be exactly 1 element due to the invariant, in which case we just return it directly
        builtins.elemAt list start;
  in
    if list == []
    # Calling binaryMerge as below would not satisfy its invariant
    then {}
    else binaryMerge 0 (builtins.length list);

  # Test our functions
  tests = debug.runTests {
    testJoinPaths = {
      expr = joinPaths ["a" "b" "c"];
      expected = "a-b-c";
    };
    testJoinPathsEmpty = {
      expr = joinPaths [];
      expected = "";
    };
    testFlattenOneLevel = {
      expr = flattenOneLevel {
        a = {
          b = 1;
          c = {
            d = 3;
            e = 4;
          };
        };
        x = {y = 25;};
        z = 26;
      };
      expected = [
        {
          a-b = 1;
          a-c = {
            d = 3;
            e = 4;
          };
        }
        {x-y = 25;}
        {z = 26;}
      ];
    };
    testFlatten = {
      expr = flatten {
        a = {
          b = 1;
          c = {
            d = 3;
            e = 4;
          };
        };
        x = {y = 25;};
        z = 26;
      };
      expected = {
        a-b = 1;
        a-c-d = 3;
        a-c-e = 4;
        x-y = 25;
        z = 26;
      };
    };
  };
}
