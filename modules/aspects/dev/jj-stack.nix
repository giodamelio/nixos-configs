_: {
  den.aspects.jj-stack.homeManager = {
    programs.jujutsu.settings = {
      aliases = {
        "bottom" = {
          definition = ["move-to" "stack_segment_bottom()"];
          doc = "Move to the bottom of the current stack segment, stack_segment_bottom()";
        };
        "top" = {
          definition = ["move-to" "stack_segment_top()"];
          doc = "Move to the top of the current stack segment, stack_segment_top()";
        };
        "sb" = {
          definition = ["stack-bookmarks"];
          doc = "Shorthand for stack-bookmarks";
        };
        "stack-bookmarks" = {
          definition = [
            "--config"
            "revsets.log=substack()"
            "log"
            "--no-graph"
            "--reversed"
            "-T"
            ''if(local_bookmarks, local_bookmarks.map(|b| b.name()).join(" ") ++ " ", "")''
          ];
          doc = "Local bookmark names in substack(@), oldest first, space-separated";
        };
      };

      revset-aliases = {
        "stack_heads()" = {
          definition = "stack_heads(@)";
          doc = "Newest mutable commits at or ahead of the working copy";
        };
        "stack_heads(to)" = {
          definition = "heads(mutable() & to::)";
          doc = "Newest mutable commits at or ahead of to";
        };
        "stack_top()" = {
          definition = "stack_top(@)";
          doc = "Newest mutable, single commit at or ahead of the working copy";
        };
        "stack_top(to)" = {
          definition = "exactly(stack_heads(to), 1)";
          doc = "Newest mutable, single commit at or ahead of to";
        };
        "stack_bottom(to)" = {
          definition = "roots(mutable() & ::to)";
          doc = "Oldest mutable commits at or behind to";
        };
        "stack_bottom()" = {
          definition = "stack_bottom(@)";
          doc = "Oldest mutable commits at or behind the working copy";
        };
        # Segments stop at merges so top/bottom resolve to one commit under a megamerge
        "stack_segment_bottom(to)" = {
          definition = "roots((mutable() & ::to ~ ::(merges() & mutable() & ::to)) | (to & merges() & mutable()))";
          doc = "Oldest mutable commit at or behind to, after the nearest merge (to itself when it is a merge)";
        };
        "stack_segment_bottom()" = {
          definition = "stack_segment_bottom(@)";
          doc = "Oldest mutable commit at or behind the working copy, after the nearest merge";
        };
        "stack_segment_top(to)" = {
          definition = "exactly(heads(mutable() & to:: ~ (merges() & mutable() & (to:: ~ to))::), 1)";
          doc = "Newest mutable, single commit at or ahead of to, before the next merge";
        };
        "stack_segment_top()" = {
          definition = "stack_segment_top(@)";
          doc = "Newest mutable, single commit at or ahead of the working copy, before the next merge";
        };
        "stack(to)" = {
          definition = "stack_bottom(to)::stack_top(to)";
          doc = "Full stack containing to, from stack_bottom(to) to stack_top(to)";
        };
        "stack()" = {
          definition = "stack(@)";
          doc = "Full stack containing the working copy, from its bottom to its top";
        };
        "substack(to)" = {
          definition = "stack_bottom(to)::to";
          doc = "Stack containing to, from stack_bottom(to) through to";
        };
        "substack()" = {
          definition = "substack(@)";
          doc = "Stack from its bottom through the working copy";
        };
        "tree()" = {
          definition = "tree(@)";
          doc = "Full tree (all stacks) containing the working copy";
        };
        "tree(to)" = {
          definition = "reachable(to, mutable())";
          doc = "Full tree (all stacks) containing to";
        };
      };
    };
  };
}
