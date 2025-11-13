{
  pkgs,
  osConfig ? null,
  ...
}: let
  inherit (pkgs) lib;

  # Check if zed-editor is in system packages
  hasZedEditor = osConfig != null && lib.elem pkgs.zed-editor osConfig.environment.systemPackages;
in {
  home.packages = with pkgs; [
    dust
    procs
  ];

  home.shellAliases =
    {
      tree = "eza --tree";
      du = "dust";
      ps = pkgs.lib.getExe pkgs.procs;
      fdg = "fd --glob";

      # Claude Code
      cc = "claude";
      ccr = "claude --resume";
      ccc = "claude --continue";
    }
    // lib.optionalAttrs hasZedEditor {
      zed = "zeditor";
    };

  # Improved version of eza tree for zsh that uses a pager
  # Aliases are at 1100, so going after that overrides them
  # Args: -R color -F exits if content is less then one page -i case insensitive search
  programs.zsh.initContent = lib.mkOrder 1200 ''
    # Override the alias with a better version that uses a pager
    unalias tree
    tree() {
      eza --tree --color=always $@ | less -RFi
    }
  '';

  programs = {
    # ls
    eza = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    ripgrep.enable = true; # grep
    bat.enable = true; # cat
  };
}
