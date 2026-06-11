# modern-coreutils-replacements — eza/bat/ripgrep/dust/procs and friends, with
# aliases. Converted from nix/modules/home/modern-coreutils-replacements.nix.
# `osConfig` is provided automatically by the HM-on-NixOS integration.
#
# modern-coreutils-replacements-system (below) is deliberately a SEPARATE
# aspect, not a `.nixos` half of this one: this aspect attaches to users, and
# den forwards a user aspect's nixos half to the host — folding would silently
# install the system packages on every host whose user has the HM aliases
# (e.g. cesium, which never imported the system variant under Blueprint).
_: {
  # System-wide copies of the replacements, for root/other users. Converted
  # from nix/modules/nixos/modern-coreutils-replacements.nix; attaches to hosts
  # (currently cadmium).
  den.aspects.modern-coreutils-replacements-system.nixos = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      fd # find
      procs # ps
      sd # sed
      dust # du
    ];
  };

  den.aspects.modern-coreutils-replacements.homeManager = {
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
  };
}
