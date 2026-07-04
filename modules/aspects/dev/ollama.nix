# ollama — local LLM server with ROCm acceleration. Converted from
# nix/modules/nixos/ollama.nix.
_: {
  den.aspects.ollama.nixos = {pkgs, ...}: {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-rocm;

      environmentVariables.OLLAMA_KEEP_ALIVE = "10m";
    };
  };

  den.aspects.ollama.homeManager = {pkgs, ...}: {
    home.packages = [
      # A binary rather than home.shellAliases so nushell gets it too; `ollama
      # stop` takes exactly one model, so unloading all of them needs a loop.
      (pkgs.writeShellApplication {
        name = "ollama-stop-all";
        runtimeInputs = with pkgs; [coreutils gawk findutils];
        text = ''
          ollama ps | tail -n +2 | awk '{print $1}' | xargs -r -n1 ollama stop
        '';
      })
    ];
  };
}
