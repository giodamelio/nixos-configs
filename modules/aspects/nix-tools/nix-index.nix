# nix-index — command-not-found plus comma (`,`) backed by the nix-index
# database. cadmium builds the index nightly for the exact nixpkgs this flake
# pins; cesium (low-power travel laptop) fetches the community-prebuilt database
# daily instead. Either way the database lands at ~/.cache/nix-index/files,
# where plain nix-index, nix-locate and comma read it — so we no longer import
# the nix-index-database flake module, whose wrappers baked a frozen store
# database into the tools and clobbered the cache symlink (see tmp/TODO.md).
{inputs, ...}: {
  den.aspects.nix-index = {host, ...}: {
    homeManager = {pkgs, ...}: let
      buildLocally = host.name == "cadmium";

      # cadmium: build the index for our pinned nixpkgs. NIXPKGS_ALLOW_UNFREE
      # keeps parity with the unfree packages this machine actually installs.
      nix-index-build = pkgs.writeShellApplication {
        name = "nix-index-update";
        runtimeInputs = [pkgs.nix-index];
        text = ''
          export NIXPKGS_ALLOW_UNFREE=1
          nix-index --nixpkgs ${inputs.nixpkgs}
        '';
      };

      # cesium: download the latest community-prebuilt database.
      nix-index-fetch = pkgs.writeShellApplication {
        name = "nix-index-update";
        runtimeInputs = [pkgs.wget];
        text = ''
          mkdir -p "$HOME/.cache/nix-index"
          cd "$HOME/.cache/nix-index"
          filename="index-$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"
          wget -nv -N "https://github.com/nix-community/nix-index-database/releases/latest/download/$filename"
          ln -sf "$filename" files
        '';
      };

      nix-index-update =
        if buildLocally
        then nix-index-build
        else nix-index-fetch;
    in {
      programs.nix-index = {
        enable = true;
        enableZshIntegration = true;
      };

      home.packages = [pkgs.comma];

      systemd.user.services.nix-index-update = {
        Unit = {
          Description = "Refresh the nix-index database";
          ConditionACPower = true;
        };

        Service = {
          Type = "oneshot";
          ExecStart = "${nix-index-update}/bin/nix-index-update";
        };
      };

      systemd.user.timers.nix-index-update = {
        Unit.Description = "Refresh the nix-index database";
        Timer = {
          OnCalendar = "*-*-* 03:00:00";
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
