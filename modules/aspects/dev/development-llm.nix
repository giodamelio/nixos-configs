{den, ...}: {
  den.aspects.development-llm.includes = [
    den.aspects.codex
    den.aspects.claude-code
    den.aspects.llm
    den.aspects.fabric
    den.aspects.veans
  ];

  den.aspects.development-llm.homeManager = {
    programs.gio-claude-code = {
      enable = true;
      installPackage = true;
    };
  };
}
