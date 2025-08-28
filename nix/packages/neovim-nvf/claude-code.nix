{pkgs, ...}: {
  vim = {
    extraPlugins = {
      claudecode = {
        package = pkgs.vimPlugins.claudecode-nvim;
        setup = "require('claudecode').setup()";
      };
    };

    keybindingTree = {
      groups = {
        "<leader>" = {
          groups = {
            "c" = {
              desc = "Claude Code";
              defaults = {lua = false;};
              keys = {
                "c" = {
                  desc = "Toggle Claude";
                  cmd = "<cmd>ClaudeCode<cr>";
                };
                "f" = {
                  desc = "Focus Claude";
                  cmd = "<cmd>ClaudeCodeFocus<cr>";
                };
                "r" = {
                  desc = "Resume Claude";
                  cmd = "<cmd>ClaudeCode --resume<cr>";
                };
                "C" = {
                  desc = "Continue Claude";
                  cmd = "<cmd>ClaudeCode --continue<cr>";
                };
                "m" = {
                  desc = "Select model";
                  cmd = "<cmd>ClaudeCodeSelectModel<cr>";
                };
                "b" = {
                  desc = "Add buffer";
                  cmd = "<cmd>ClaudeCodeAdd %<cr>";
                };
                "a" = {
                  desc = "Accept diff";
                  cmd = "<cmd>ClaudeCodeDiffAccept<cr>";
                };
                "d" = {
                  desc = "Deny diff";
                  cmd = "<cmd>ClaudeCodeDiffDeny<cr>";
                };
                "s" = {
                  desc = "Send selection";
                  mode = ["v"];
                  cmd = "<cmd>ClaudeCodeSend<cr>";
                };
              };
            };
          };
        };
      };
    };
  };
}
