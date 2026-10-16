{
  den,
  lib,
  ...
}: {
  den.aspects.opencode = {
    policies.desktop = {host, ...}:
      lib.optional (host.role == "desktop") (den.lib.policy.include den.aspects.opencode-desktop);

    includes = [den.aspects.opencode.policies.desktop];

    homeManager = {perSystem, ...}: {
      home.packages = [perSystem.llm-agents.opencode2];
      home.shellAliases.opencode = "opencode2";
    };
  };

  den.aspects.opencode-desktop.homeManager = {perSystem, ...}: {
    home.packages = [perSystem.llm-agents.opencode2-desktop];
  };
}
