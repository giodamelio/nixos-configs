{inputs, ...}: {
  perSystem = {
    pkgs,
    config,
    ...
  }: {
    packages.agent-dms = inputs.self.lib.writeNushellApplication pkgs {
      name = "agent-dms";
      runtimeInputs = [
        config.packages.himalaya
        pkgs.stalwart-cli
        pkgs.libsecret
        # op comes from the host: the NixOS module's setgid wrapper is what
        # lets it talk to the desktop app.
        pkgs.jujutsu
        pkgs.git
        pkgs.coreutils
      ];
      stdin = true;
      source = ''
        const server = "https://agent-dms.gio.ninja"
        const domain = "agent-dms.gio.ninja"
        # Every project inbox is shared with this account, for Thunderbird.
        const owner = "gio"
        # Holds the password from carbon's /var/lib/stalwart/recovery-admin.
        const admin_item = "agent-dms admin"

        ${builtins.readFile ./agent-dms.nu}
      '';
      meta = {
        description = "An inbox per project for coding agents, on the agent-dms Stalwart server";
        mainProgram = "agent-dms";
        platforms = pkgs.lib.platforms.linux;
      };
    };
  };
}
