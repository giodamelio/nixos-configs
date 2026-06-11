# claude-code — the programs.gio-claude-code option set: a jailed `claude`
# wrapper plus optional agent/command symlinks. Converted from
# nix/modules/home/claude-code/default.nix.
#   - `flake.packages.<sys>.jailed-claude` -> `perSystem.self.jailed-claude`.
#   - `perSystem.llm-agents.{claude-code,rtk}` are module args from the
#     per-system aspect.
#
# Note: the Blueprint module shipped example agent/command markdown beside it,
# but those are only wired in when a host sets `programs.gio-claude-code.agents`
# / `.commands` explicitly (cesium does not), so no asset files are carried here.
_: {
  den.aspects.claude-code.homeManager = {
    config,
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    jailedClaude = perSystem.self.jailed-claude;
    claudeCode = perSystem.llm-agents.claude-code;

    # Wrap jailed-claude so it's also available as "claude" in PATH
    claudeWrapper = pkgs.symlinkJoin {
      name = "claude-wrapper";
      paths = [jailedClaude];
      postBuild = ''
        ln -s ${lib.getExe jailedClaude} $out/bin/claude
        # Also put the original (non-jailed) one in PATH as "claude-original"
        ln -s ${lib.getExe claudeCode} $out/bin/claude-original
      '';
    };
  in {
    options.programs.gio-claude-code = {
      enable = lib.mkEnableOption "Claude Code configuration management";

      installPackage = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to install the Claude Code package";
      };

      agents = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = {};
        description = "Agent markdown files to symlink (name -> path)";
        example = lib.literalExpression ''
          {
            postgres-db-expert = ./agents/postgres-db-expert.md;
            my-custom-agent = ./agents/my-custom-agent.md;
          }
        '';
      };

      commands = lib.mkOption {
        type = lib.types.attrsOf (lib.types.either lib.types.path (lib.types.attrsOf lib.types.path));
        default = {};
        description = "Command files to symlink";
        example = lib.literalExpression ''
          {
            plan-save = ./commands/plan-save.md;
            pre-commit = {
              markdown = ./commands/pre-commit.md;
              script = ./commands/pre-commit.sh;
            };
          }
        '';
      };
    };

    config = lib.mkIf config.programs.gio-claude-code.enable {
      home.packages = [
        claudeWrapper
        perSystem.llm-agents.rtk
      ];

      home.shellAliases = {
        claude = lib.getExe jailedClaude;
        claude-dangerous = lib.getExe claudeCode;
      };

      # Dynamically link agents and commands using home.file
      home.file =
        # Link agents
        lib.mapAttrs' (
          name: path: lib.nameValuePair ".claude/agents/${name}.md" {source = path;}
        )
        config.programs.gio-claude-code.agents
        //
        # Link commands (handle both simple paths and attrsets with markdown/script)
        lib.concatMapAttrs (
          name: value:
            if lib.isPath value
            then {
              ".claude/commands/${name}.md" = {
                source = value;
              };
            }
            else
              lib.optionalAttrs (value ? markdown) {
                ".claude/commands/${name}.md" = {
                  source = value.markdown;
                };
              }
              // lib.optionalAttrs (value ? script) {
                ".claude/commands/${name}.sh" = {
                  source = value.script;
                  executable = true;
                };
              }
        )
        config.programs.gio-claude-code.commands;
    };
  };
}
