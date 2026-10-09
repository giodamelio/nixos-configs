{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.system-info = inputs.self.lib.writeNushellApplication pkgs {
      name = "system-info";
      runtimeInputs = with pkgs; [duf inxi util-linux iproute2 getent iw systemd coreutils];
      source = builtins.readFile ./system-info.nu;

      meta.description = "Pretty overviews of the local system";
      meta.platforms = pkgs.lib.platforms.linux;
      meta.mainProgram = "system-info";
    };
  };
}
