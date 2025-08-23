{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.claude-code = {
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

  config = lib.mkIf config.programs.claude-code.enable {
    # Install package if requested
    home.packages = lib.optional config.programs.claude-code.installPackage pkgs.claude-ai;

    # Dynamically link agents and commands using home.file
    home.file =
      # Link agents
      lib.mapAttrs' (
        name: path:
          lib.nameValuePair ".claude/agents/${name}.md" {source = path;}
      )
      config.programs.claude-code.agents
      //
      # Link commands (handle both simple paths and attrsets with markdown/script)
      lib.concatMapAttrs (name: value:
        if lib.isPath value
        then {".claude/commands/${name}.md" = {source = value;};}
        else
          lib.optionalAttrs (value ? markdown) {
            ".claude/commands/${name}.md" = {source = value.markdown;};
          }
          // lib.optionalAttrs (value ? script) {
            ".claude/commands/${name}.sh" = {
              source = value.script;
              executable = true;
            };
          })
      config.programs.claude-code.commands;
  };
}
