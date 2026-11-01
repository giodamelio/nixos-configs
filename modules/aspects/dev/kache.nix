{inputs, ...}: {
  den.aspects.kache.nixos = {
    lib,
    pkgs,
    ...
  }: {
    imports = [inputs.kache.nixosModules.default];

    services.kache = {
      enable = true;
      # The module's default resolves to nixpkgs' kache 1.x unless the overlay is applied.
      package = inputs.kache.packages.${pkgs.stdenv.hostPlatform.system}.kache;
      rustcWrapper = true;
      daemon.enable = true;
      settings.cache = {
        local_store = "/home/giodamelio/.cache/builds/kache";
        # Off the store dir (the default) so the jail's read-only store bind
        # never exposes the daemon socket.
        runtime_dir = "/run/user/1000/kache";
        # The jail's read-only open needs index.db-wal/-shm, which only exist
        # while the daemon holds the index open.
        daemon_idle_timeout_secs = 0;
      };
    };

    # The daemon exits cleanly when its config file changes, so on-failure
    # would leave it down after every rebuild that touches the config.
    systemd.user.services.kache.serviceConfig.Restart = lib.mkForce "always";
  };
}
